package ma.foorsa.student

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.annotation.RequiresApi
import android.os.VibrationEffect.Composition.PRIMITIVE_CLICK as CLICK
import android.os.VibrationEffect.Composition.PRIMITIVE_LOW_TICK as LOW_TICK
import android.os.VibrationEffect.Composition.PRIMITIVE_QUICK_RISE as QUICK_RISE
import android.os.VibrationEffect.Composition.PRIMITIVE_THUD as THUD
import android.os.VibrationEffect.Composition.PRIMITIVE_TICK as TICK

/**
 * The admission reveal's sense of touch (admissionFeedback.ts in the portal).
 * Each name is a texture, played with the best the phone's actuator offers:
 * haptic primitives (API 30+), the system's tuned click effects (API 29),
 * an amplitude waveform (API 26), a plain pulse before that.
 *
 * [play] answers false only when there is nothing to play with, so the Dart
 * side can fall back to HapticFeedback. A phone whose owner has turned touch
 * feedback off stays still and answers true: that choice is theirs.
 */
class ShellHaptics(private val context: Context) {

    private class Step(val primitive: Int, val scale: Float, val delayMs: Int = 0)

    /**
     * [compositions] are tried in order until the actuator supports every
     * primitive in one; THUD and LOW_TICK need API 31 and a capable motor.
     * [timings]/[amplitudes] (0–255) are the waveform for older phones.
     */
    private class Texture(
        val compositions: List<List<Step>>,
        val predefined: Int,
        val timings: LongArray,
        val amplitudes: IntArray,
    )

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

    fun play(touch: String): Boolean {
        val texture = TEXTURES[touch] ?: return false
        val vibrator = vibrator ?: return false
        return try {
            if (!vibrator.hasVibrator()) return false
            if (touchFeedbackOff()) return true
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                    val steps = texture.compositions.firstOrNull { supported(vibrator, it) }
                    vibrate(vibrator, steps?.let(::compose) ?: VibrationEffect.createPredefined(texture.predefined))
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    vibrate(vibrator, VibrationEffect.createPredefined(texture.predefined))
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                    vibrate(vibrator, waveform(vibrator, texture))
                else -> {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(texture.timings, -1)
                }
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun touchFeedbackOff(): Boolean = try {
        Settings.System.getInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0
    } catch (_: Throwable) {
        false
    }

    @RequiresApi(Build.VERSION_CODES.R)
    @SuppressLint("InlinedApi")
    private fun supported(vibrator: Vibrator, steps: List<Step>): Boolean {
        val ids = steps.map { it.primitive }.distinct()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && ids.any { it == THUD || it == LOW_TICK }) return false
        return vibrator.areAllPrimitivesSupported(*ids.toIntArray())
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun compose(steps: List<Step>): VibrationEffect {
        val composition = VibrationEffect.startComposition()
        for (step in steps) composition.addPrimitive(step.primitive, step.scale, step.delayMs)
        return composition.compose()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun waveform(vibrator: Vibrator, texture: Texture): VibrationEffect =
        if (vibrator.hasAmplitudeControl()) {
            VibrationEffect.createWaveform(texture.timings, texture.amplitudes, -1)
        } else {
            VibrationEffect.createWaveform(texture.timings, -1)
        }

    /** Played as touch feedback, so the system's touch intensity applies. */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun vibrate(vibrator: Vibrator, effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(
                effect,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
    }

    private companion object {
        // The ids are compile-time constants, each played only behind the
        // SDK check that introduced it. Each timing list starts with a 0 ms
        // wait; amplitudes pair with it.
        @SuppressLint("InlinedApi")
        val TEXTURES: Map<String, Texture> = mapOf(
            // A fingertip settling on the wax.
            "press" to Texture(
                listOf(listOf(Step(LOW_TICK, 0.6f)), listOf(Step(TICK, 0.5f))),
                VibrationEffect.EFFECT_TICK,
                longArrayOf(0, 10), intArrayOf(0, 90),
            ),
            // The seal snaps: two fractures 26 ms apart, then the wax lets go.
            "crack" to Texture(
                listOf(
                    listOf(Step(CLICK, 1f), Step(TICK, 0.7f, 14), Step(LOW_TICK, 0.45f, 18)),
                    listOf(Step(CLICK, 1f), Step(TICK, 0.7f, 14)),
                ),
                VibrationEffect.EFFECT_HEAVY_CLICK,
                longArrayOf(0, 14, 12, 10), intArrayOf(0, 255, 0, 140),
            ),
            // A flap standing upright under the finger: a notch.
            "detent" to Texture(
                listOf(listOf(Step(TICK, 0.5f))),
                VibrationEffect.EFFECT_TICK,
                longArrayOf(0, 6), intArrayOf(0, 110),
            ),
            // A flap coming to rest on the table.
            "land" to Texture(
                listOf(listOf(Step(THUD, 0.55f)), listOf(Step(CLICK, 0.45f))),
                VibrationEffect.EFFECT_CLICK,
                longArrayOf(0, 14), intArrayOf(0, 170),
            ),
            // Paper against the pocket, many times a second: barely there.
            "grain" to Texture(
                listOf(listOf(Step(LOW_TICK, 0.28f)), listOf(Step(TICK, 0.18f))),
                VibrationEffect.EFFECT_TICK,
                longArrayOf(0, 4), intArrayOf(0, 60),
            ),
            // The letter rising out of the pocket and slipping free.
            "release" to Texture(
                listOf(
                    listOf(Step(QUICK_RISE, 0.45f), Step(TICK, 0.8f)),
                    listOf(Step(TICK, 0.4f), Step(CLICK, 0.6f, 24)),
                ),
                VibrationEffect.EFFECT_CLICK,
                longArrayOf(0, 8, 24, 14), intArrayOf(0, 90, 0, 150),
            ),
            // In the student's hands: two taps with the chime's two bells.
            "arrive" to Texture(
                listOf(listOf(Step(CLICK, 0.6f), Step(CLICK, 1f, 118))),
                VibrationEffect.EFFECT_DOUBLE_CLICK,
                longArrayOf(0, 16, 114, 28), intArrayOf(0, 140, 0, 230),
            ),
        )
    }
}
