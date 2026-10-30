package ma.foorsa.student

import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Arrays
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The guided scanner's live reading on Android (live_text_reader.dart): ML
 * Kit's Latin text model, bundled in the app by com.google.mlkit:text-recognition,
 * so it reads offline and in China, with no model to download and no Google
 * Play services needed. The scanner sends the luminance of the page it sees a
 * few times a second; what is read goes back to Dart and nowhere else, and is
 * never logged.
 */
class LiveTextReader {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)

    // Created, used and closed on the executor only.
    private var recognizer: TextRecognizer? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read" -> read(call, result)
            "close" -> {
                executor.execute { closeRecognizer() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun read(call: MethodCall, result: MethodChannel.Result) {
        val luma = call.argument<ByteArray>("luma")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val rotation = call.argument<Int>("rotation") ?: -1
        if (luma == null || width < MIN_SIDE || height < MIN_SIDE || width > MAX_SIDE || height > MAX_SIDE ||
            width % 2 != 0 || height % 2 != 0 || luma.size != width * height || rotation !in ROTATIONS
        ) {
            result.success(mapOf("error" to "invalid_frame"))
            return
        }
        if (!busy.compareAndSet(false, true)) {
            result.success(mapOf("busy" to true))
            return
        }
        executor.execute {
            try {
                // NV21 with neutral chroma: the model reads luminance only.
                val nv21 = ByteArray(width * height * 3 / 2)
                System.arraycopy(luma, 0, nv21, 0, width * height)
                Arrays.fill(nv21, width * height, nv21.size, NEUTRAL_CHROMA)
                val image = InputImage.fromByteArray(nv21, width, height, rotation, InputImage.IMAGE_FORMAT_NV21)
                val client = recognizer ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    .also { recognizer = it }
                client.process(image)
                    .addOnSuccessListener(executor) { text -> reply(result, encode(text, width, height, rotation)) }
                    .addOnFailureListener(executor) { reply(result, mapOf("error" to "recognition_failed")) }
            } catch (_: Throwable) {
                reply(result, mapOf("error" to "recognition_failed"))
            }
        }
    }

    /** Lines in pixels of the image the model read: the crop turned by [rotation]. */
    private fun encode(text: Text, width: Int, height: Int, rotation: Int): Map<String, Any> {
        val turned = rotation == 90 || rotation == 270
        val lines = ArrayList<Map<String, Any>>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                if (lines.size >= MAX_LINES) break
                val box = line.boundingBox ?: continue
                lines.add(
                    mapOf(
                        "text" to line.text.take(MAX_TEXT),
                        "left" to box.left,
                        "top" to box.top,
                        "right" to box.right,
                        "bottom" to box.bottom,
                    )
                )
            }
        }
        return mapOf(
            "width" to (if (turned) height else width),
            "height" to (if (turned) width else height),
            "lines" to lines,
        )
    }

    private fun reply(result: MethodChannel.Result, value: Any) {
        busy.set(false)
        main.post { result.success(value) }
    }

    private fun closeRecognizer() {
        try {
            recognizer?.close()
        } catch (_: Throwable) {
            // Already closed with the engine.
        }
        recognizer = null
    }

    companion object {
        private const val MIN_SIDE = 32
        private const val MAX_SIDE = 4096
        private const val MAX_LINES = 120
        private const val MAX_TEXT = 200
        // 0x80: the middle of the chroma range, no colour.
        private const val NEUTRAL_CHROMA: Byte = -128
        private val ROTATIONS = setOf(0, 90, 180, 270)
    }
}
