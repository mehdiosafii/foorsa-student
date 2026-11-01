package ma.foorsa.student

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/**
 * The guided scanner's photo made ready for the portal (scan_photo.dart):
 * turned upright as its EXIF orientation says, scaled down to at most
 * `maxEdge` pixels on its long side, and encoded as a JPEG with no metadata.
 * The camera's own photo comes back byte for byte when it is already upright
 * and that small. Nothing is sharpened, whitened or otherwise changed: the
 * portal crops the page and the CRM's AI scan relights it.
 *
 * Off the main thread; a photo that cannot be read, or memory that runs out
 * on an old phone, answers an error, and the shell then sends the camera's
 * own file.
 */
class ScanPhoto {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "prepare") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val maxEdge = (call.argument<Int>("maxEdge") ?: DEFAULT_EDGE).coerceIn(MIN_EDGE, MAX_EDGE)
        val quality = (call.argument<Int>("quality") ?: DEFAULT_QUALITY).coerceIn(50, 100)
        if (path.isNullOrEmpty()) {
            result.success(mapOf("error" to "invalid"))
            return
        }
        executor.execute {
            val reply: Map<String, Any> = try {
                prepare(File(path), maxEdge, quality)
            } catch (_: OutOfMemoryError) {
                mapOf("error" to "memory")
            } catch (_: Throwable) {
                mapOf("error" to "failed")
            }
            main.post { result.success(reply) }
        }
    }

    private fun prepare(file: File, maxEdge: Int, quality: Int): Map<String, Any> {
        if (!file.isFile) return mapOf("error" to "missing")
        val orientation = try {
            ExifInterface(file.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
            )
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) return mapOf("error" to "unreadable")
        val longEdge = max(width, height)
        val upright = orientation == ExifInterface.ORIENTATION_NORMAL ||
            orientation == ExifInterface.ORIENTATION_UNDEFINED
        if (longEdge <= maxEdge && upright) {
            return mapOf("bytes" to file.readBytes(), "width" to width, "height" to height, "reencoded" to false)
        }
        // Decode at the largest power-of-two step that stays at or above the
        // target (the JPEG decoder's own scaling keeps fine print), then
        // scale and turn in one filtered pass.
        var sample = 1
        while (longEdge / (sample * 2) >= maxEdge) sample *= 2
        val decoded = BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        ) ?: return mapOf("error" to "unreadable")
        val scale = min(1f, maxEdge.toFloat() / max(decoded.width, decoded.height))
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.setRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
        }
        matrix.postScale(scale, scale)
        val ready = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (ready !== decoded) decoded.recycle()
        val out = ByteArrayOutputStream(ready.width * ready.height / 4)
        val encoded = ready.compress(Bitmap.CompressFormat.JPEG, quality, out)
        val readyWidth = ready.width
        val readyHeight = ready.height
        ready.recycle()
        if (!encoded) return mapOf("error" to "encode")
        return mapOf("bytes" to out.toByteArray(), "width" to readyWidth, "height" to readyHeight, "reencoded" to true)
    }

    companion object {
        private const val DEFAULT_EDGE = 3264
        private const val MIN_EDGE = 640
        private const val MAX_EDGE = 8192
        private const val DEFAULT_QUALITY = 92
    }
}
