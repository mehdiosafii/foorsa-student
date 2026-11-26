package ma.foorsa.crm

import android.content.Intent
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's one screen, and the Android half of lib/src/push.dart:
 * the Firebase token the CRM registers, and the page a tapped notification
 * opens (CrmMessagingService puts it in the intent as "route").
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingRoute: String? = null
    private var dartReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        takeRoute(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foorsa_crm/push")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    dartReady = true
                    result.success(pendingRoute)
                    pendingRoute = null
                }
                "getToken" -> token(result)
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeRoute(intent)
    }

    private fun takeRoute(intent: Intent?) {
        val route = intent?.getStringExtra(CrmMessagingService.EXTRA_ROUTE) ?: return
        intent.removeExtra(CrmMessagingService.EXTRA_ROUTE)
        if (!route.startsWith("/")) return
        val ch = channel
        if (dartReady && ch != null) ch.invokeMethod("open", route) else pendingRoute = route
    }

    /** Null when this build has no Firebase file, or Firebase cannot answer. */
    private fun token(result: MethodChannel.Result) {
        if (FirebaseApp.getApps(this).isEmpty()) {
            result.success(null)
            return
        }
        var answered = false
        try {
            FirebaseMessaging.getInstance().isAutoInitEnabled = true
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (answered) return@addOnCompleteListener
                answered = true
                result.success(if (task.isSuccessful) task.result else null)
            }
        } catch (e: Exception) {
            if (!answered) {
                answered = true
                result.success(null)
            }
        }
    }
}
