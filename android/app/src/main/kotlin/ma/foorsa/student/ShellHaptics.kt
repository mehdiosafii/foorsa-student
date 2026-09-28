package ma.foorsa.student

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.RequiresApi

/**
 * The admission reveal's sense of touch (admissionFeedback.ts in the portal),
 * made to be felt: a heartbeat while the letter waits, the seal cracking, the
 * flaps landing, a grain that grows as the letter is pulled, and a
 * celebration whose taps fall on the music's first notes.
 *
 * Each texture is an amplitude waveform. Phones without amplitude control get
 * its on/off rhythm instead, the same pulses the web uses for navigator.vibrate.
 * It plays as media vibration, the category for haptics that accompany sound
 * and animation: the system's touch-feedback switch, which silences keyboard
 * ticks, does not silence it, while the master vibration switch still does.
 *
 * [play] answers false only when there is nothing to play with, so the Dart
 * side can fall back to HapticFeedback.
 */
class ShellHaptics(private val context: Context) {

    /** [timings] start with a 0 ms wait; [amplitudes] (0–255) pair with them. */
    private class Texture(val timings: LongArray, val amplitudes: IntArray, val pulses: LongArray)

    private val vibrator: Vibrator? by lazy {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                    ?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (_: Throwable) {
            null
        }
    }

    /** [level] (0–1) is how far the letter has come; only the grain reads it. */
    fun play(touch: String, level: Double = 1.0): Boolean {
        val texture = textureFor(touch, level) ?: return false
        val vibrator = vibrator ?: return false
        return try {
            if (!vibrator.hasVibrator()) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = if (vibrator.hasAmplitudeControl()) {
                    VibrationEffect.createWaveform(texture.timings, texture.amplitudes, -1)
                } else {
                    VibrationEffect.createWaveform(texture.pulses, -1)
                }
                vibrate(vibrator, effect)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(texture.pulses, -1)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun vibrate(vibrator: Vibrator, effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_MEDIA))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(
                effect,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
    }

    companion object {
        /** The textures the reveal names; admissionFeedback.ts keeps the same list. */
        val TOUCHES = setOf("heartbeat", "press", "crack", "detent", "unfold", "land", "grain", "release", "arrive", "select")

        private val TEXTURES: Map<String, Texture> = mapOf(
            // Lub-dub: a strong beat, then a softer one.
            "heartbeat" to Texture(longArrayOf(0, 55, 120, 38), intArrayOf(0, 235, 0, 150), longArrayOf(0, 55, 120, 38)),
            // A fingertip settling on the wax.
            "press" to Texture(longArrayOf(0, 24), intArrayOf(0, 150), longArrayOf(0, 26)),
            // The seal snaps: a hard fracture, a second, and the wax letting go.
            "crack" to Texture(longArrayOf(0, 28, 22, 18, 40, 60), intArrayOf(0, 255, 0, 190, 0, 70), longArrayOf(0, 70, 45, 34)),
            // A flap standing upright under the finger: a notch.
            "detent" to Texture(longArrayOf(0, 18), intArrayOf(0, 170), longArrayOf(0, 24)),
            // The flaps swinging open: a swell that settles.
            "unfold" to Texture(
                longArrayOf(0, 60, 60, 60, 60, 60, 60, 70),
                intArrayOf(0, 40, 75, 110, 140, 115, 80, 40),
                longArrayOf(0, 18, 30, 22, 30, 28, 30, 36),
            ),
            // A flap coming to rest on the table.
            "land" to Texture(longArrayOf(0, 40), intArrayOf(0, 220), longArrayOf(0, 46)),
            // The letter rising out of the pocket and slipping free.
            "release" to Texture(longArrayOf(0, 30, 30, 30, 30, 50), intArrayOf(0, 70, 120, 170, 220, 255), longArrayOf(0, 28, 36, 58)),
            // In the student's hands: the downbeat, then the melody's first three notes.
            "arrive" to Texture(
                longArrayOf(0, 90, 535, 30, 282, 30, 283, 50),
                intArrayOf(0, 255, 0, 160, 0, 185, 0, 235),
                longArrayOf(0, 90, 535, 30, 282, 30, 283, 50),
            ),
            "select" to Texture(longArrayOf(0, 22), intArrayOf(0, 180), longArrayOf(0, 26)),
        )

        /** Paper against the pocket grows longer and stronger as the letter comes out. */
        private fun textureFor(touch: String, level: Double): Texture? {
            if (touch != "grain") return TEXTURES[touch]
            val l = level.coerceIn(0.0, 1.0)
            val ms = (12 + 16 * l).toLong()
            return Texture(longArrayOf(0, ms), intArrayOf(0, (80 + 150 * l).toInt()), longArrayOf(0, (16 + 18 * l).toLong()))
        }
    }
}
