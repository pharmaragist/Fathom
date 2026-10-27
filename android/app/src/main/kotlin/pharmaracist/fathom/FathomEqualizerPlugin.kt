package pharmaracist.fathom

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge to a fixed ten-band equalizer.
 *
 * The platform [android.media.audiofx.Equalizer] only exposes as many bands as
 * the device audio HAL provides (usually five), so a standard ten-band graphic
 * equalizer is built on [DynamicsProcessing] instead (API 28+). On older
 * releases `attach` returns `false` and Dart falls back to the hardware bands.
 *
 * Every write reports whether the engine accepted it. A released effect, or one
 * whose session has ended, still accepts calls and processes nothing, so Dart
 * needs the answer to tell "the dial moved the audio" apart from "the dial wrote
 * into a dead object" and re-attach instead of staying silently unresponsive.
 */
class FathomEqualizerPlugin : MethodChannel.MethodCallHandler {

    private var engine: Engine? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            "attach" -> result.success(attach(call))
            "isAlive" -> result.success(engine?.isAlive() ?: false)
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                result.success(engine?.setEnabled(enabled) ?: false)
            }
            "setGains" -> {
                val gains = call.argument<List<Double>>("gains").orEmpty()
                result.success(engine?.setGains(gains) ?: false)
            }
            "setGain" -> {
                val index = call.argument<Int>("index") ?: -1
                val gain = call.argument<Double>("gain") ?: 0.0
                result.success(engine?.setGain(index, gain) ?: false)
            }
            "setPreamp" -> {
                val gain = call.argument<Double>("gain") ?: 0.0
                result.success(engine?.setPreamp(gain) ?: false)
            }
            "setLimiter" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                result.success(engine?.setLimiter(enabled) ?: false)
            }
            "detach" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun attach(call: MethodCall): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val sessionId = call.argument<Int>("sessionId") ?: return false
        val bands = call.argument<List<Int>>("bands") ?: return false
        if (bands.isEmpty()) return false
        val gain = call.argument<Double>("gain") ?: 0.0
        val preamp = call.argument<Double>("preamp") ?: 0.0
        val limiter = call.argument<Boolean>("limiter") ?: true

        release()
        return try {
            engine = Engine(sessionId, bands, gain, preamp, limiter)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Unable to attach DynamicsProcessing to session $sessionId", e)
            release()
            false
        }
    }

    private fun release() {
        engine?.release()
        engine = null
    }

    private class Engine(
        sessionId: Int,
        private val bands: List<Int>,
        initialGain: Double,
        initialPreamp: Double,
        limiterEnabled: Boolean,
    ) {
        private val effect: DynamicsProcessing

        /** The enable state the app asked for, re-asserted after the platform
         *  takes exclusive control away and silently disables the effect. */
        private var enabled = true

        init {
            val builder = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                CHANNEL_COUNT,
                false,
                PRE_EQ_BANDS,
                false,
                MBC_BANDS,
                true,
                bands.size,
                true,
            )
            builder.setInputGainAllChannelsTo(initialPreamp.toFloat())
            // Declared in use even when disabled: a stage that is not in use
            // cannot be enabled later without rebuilding the whole effect, and
            // the toggle has to be instant.
            builder.setLimiterAllChannelsTo(limiter(limiterEnabled))

            val config = builder.build()
            effect = DynamicsProcessing(PRIORITY, sessionId, config)

            bands.forEachIndexed { index, hz ->
                try {
                    effect.setPostEqBandAllChannelsTo(index, band(hz, initialGain))
                } catch (e: Exception) {
                    Log.w(TAG, "Device rejected band $index ($hz Hz)", e)
                }
            }
        }

        /** Whether the effect can still be read, which a released one cannot. */
        fun isAlive(): Boolean = try {
            effect.enabled
            true
        } catch (e: Exception) {
            false
        }

        /** Re-enables the stage when the platform disabled it behind the app's
         *  back. Writes already re-assert it, so a dial is never applied to a
         *  bypassed effect. */
        private fun ensureEnabled() {
            if (!enabled) return
            try {
                if (!effect.enabled) effect.enabled = true
            } catch (e: Exception) {
                Log.w(TAG, "Unable to re-enable the equalizer", e)
            }
        }

        fun setPreamp(db: Double): Boolean = try {
            ensureEnabled()
            effect.setInputGainAllChannelsTo(db.toFloat())
            true
        } catch (e: Exception) {
            Log.w(TAG, "Unable to set the preamp", e)
            false
        }

        fun setLimiter(value: Boolean): Boolean = try {
            effect.setLimiterAllChannelsTo(limiter(value))
            true
        } catch (e: Exception) {
            Log.w(TAG, "Unable to set the limiter", e)
            false
        }

        fun setEnabled(value: Boolean): Boolean = try {
            enabled = value
            effect.enabled = value
            true
        } catch (e: Exception) {
            Log.w(TAG, "Unable to toggle equalizer", e)
            false
        }

        fun setGains(gains: List<Double>): Boolean {
            if (gains.size < bands.size) return false
            var ok = true
            bands.indices.forEach { index ->
                if (!setGain(index, gains[index])) ok = false
            }
            return ok
        }

        fun setGain(index: Int, db: Double): Boolean {
            val hz = bands.getOrNull(index) ?: return false
            return try {
                ensureEnabled()
                // A fresh band rather than a read-modify-write of the effect's
                // copy: `getPostEqBandByChannelIndex` can come back disabled or
                // stale on some HALs, and assigning `gain` to a disabled band
                // succeeds while changing nothing.
                effect.setPostEqBandAllChannelsTo(index, band(hz, db))
                true
            } catch (e: Exception) {
                Log.w(TAG, "Unable to set band $index", e)
                false
            }
        }

        fun release() {
            try {
                effect.release()
            } catch (_: Exception) {
                // The effect may already be gone if the audio session ended.
            }
        }

        private fun band(hz: Int, gain: Double) =
            DynamicsProcessing.EqBand(true, hz.toFloat(), gain.toFloat())
    }

    companion object {
        const val CHANNEL = "pharmaracist.fathom/equalizer"

        private const val TAG = "FathomEqualizer"
        private const val PRIORITY = 0
        private const val CHANNEL_COUNT = 2
        private const val PRE_EQ_BANDS = 0
        private const val MBC_BANDS = 0

        /**
         * Soft peak limiter that follows the preamp and the post EQ.
         *
         * Mirrors the constants in `FathomNativeEqualizer`: a -1 dBFS ceiling,
         * 20:1 above it, 1 ms attack, 80 ms release and no post gain. Both
         * channels share link group 1 so stereo peaks are reduced together,
         * which is what keeps the image from shifting under a peak.
         *
         * Android exposes no gain-reduction metering for this stage, so the UI
         * predicts danger from preamp plus band boost and does not claim to
         * display actual limiting.
         */
        private fun limiter(enabled: Boolean) = DynamicsProcessing.Limiter(
            /* inUse = */ true,
            enabled,
            LIMITER_LINK_GROUP,
            LIMITER_ATTACK_MS,
            LIMITER_RELEASE_MS,
            LIMITER_RATIO,
            LIMITER_THRESHOLD_DB,
            LIMITER_POST_GAIN_DB,
        )

        private const val LIMITER_LINK_GROUP = 1
        private const val LIMITER_ATTACK_MS = 1.0f
        private const val LIMITER_RELEASE_MS = 80.0f
        private const val LIMITER_RATIO = 20.0f
        private const val LIMITER_THRESHOLD_DB = -1.0f
        private const val LIMITER_POST_GAIN_DB = 0.0f
    }
}
