package ma.foorsa.student

import android.annotation.SuppressLint
import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foorsa/biometrics")
            .setMethodCallHandler { call, result ->
                if (call.method == "supportsProtectedStorage") {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                } else if (call.method == "deleteProtectedStorage") {
                    val namespace = call.argument<String>("namespace") ?: ""
                    if (!namespace.matches(Regex("foorsa_student_biometrics_v1_[a-f0-9]{32}"))) {
                        result.error("invalid_namespace", "Invalid quick sign-in storage", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // flutter_secure_storage 10.3.4 initializes its cipher even
                        // for delete(), which can prompt or fail after enrollment
                        // changes. Remove only our dedicated namespace without auth.
                        val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore")
                        keyStore.load(null)
                        keyStore.deleteEntry("$packageName.FlutterSecureStoragePluginKey.$namespace")
                        for (name in listOf(namespace, "FlutterSecureKeyStorage:$namespace",
                            "FlutterSecureStorageConfiguration:$namespace")) {
                            if (!getSharedPreferences(name, MODE_PRIVATE).edit().clear().commit()) {
                                throw IllegalStateException("Could not remove quick sign-in storage")
                            }
                        }
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("delete_failed", "Could not remove quick sign-in storage", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        // Saves a temp file into the public Downloads collection through
        // MediaStore (API 29+): no storage permission, no
        // MANAGE_EXTERNAL_STORAGE, and the system auto-suffixes duplicate
        // display names. Returns false below API 29 so the Dart side takes
        // the legacy direct-write path instead.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foorsa/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    if (Build.VERSION.SDK_INT < 29) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("path missing")
                    val name = call.argument<String>("name") ?: "download"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val values = android.content.ContentValues().apply {
                        put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                        put(android.provider.MediaStore.Downloads.MIME_TYPE, mime)
                        put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                        put(
                            android.provider.MediaStore.Downloads.RELATIVE_PATH,
                            android.os.Environment.DIRECTORY_DOWNLOADS
                        )
                    }
                    val uri = contentResolver.insert(
                        android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        values
                    ) ?: throw IllegalStateException("MediaStore insert failed")
                    try {
                        contentResolver.openOutputStream(uri).use { out ->
                            java.io.FileInputStream(java.io.File(path)).use { input ->
                                input.copyTo(out ?: throw IllegalStateException("no output stream"))
                            }
                        }
                        val published = contentResolver.update(uri, android.content.ContentValues().apply {
                            put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                        }, null, null)
                        if (published != 1) throw IllegalStateException("Download could not be published")
                    } catch (e: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw e
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
            }
        // The portal's textures, by name (shell_haptics.dart). Answers false
        // when the phone cannot play one, so Dart falls back to system impacts.
        val haptics = ShellHaptics(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foorsa/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // { touch, level } from current Dart; a bare name from older builds.
                val args = call.arguments
                val map = args as? Map<*, *>
                val touch = map?.get("touch") as? String ?: args as? String ?: ""
                val level = (map?.get("level") as? Number)?.toDouble() ?: 1.0
                result.success(haptics.play(touch, level))
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        requestHighestRefreshRate()
    }

    /**
     * Android renders an app at 60Hz unless it explicitly asks for more, so
     * animations look capped on 90/120Hz panels. Pick the fastest display mode
     * that keeps the CURRENT resolution (never trade pixels for Hz), and
     * re-assert it on resume because the system can reset it. No-op on 60Hz
     * devices and on displays that refuse mode changes.
     */
    @SuppressLint("NewApi")
    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            @Suppress("DEPRECATION")
            val display: Display? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
                else windowManager.defaultDisplay
            val active = display?.mode ?: return
            val fastest = display.supportedModes
                ?.filter {
                    it.physicalWidth == active.physicalWidth &&
                        it.physicalHeight == active.physicalHeight
                }
                ?.maxByOrNull { it.refreshRate } ?: return
            if (fastest.refreshRate <= active.refreshRate + 0.1f) return
            val params = window.attributes
            params.preferredDisplayModeId = fastest.modeId
            params.preferredRefreshRate = fastest.refreshRate
            window.attributes = params
        } catch (_: Throwable) {
            // Best effort — a locked display simply stays at its default rate.
        }
    }
}
