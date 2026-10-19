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
 */
class FathomEqualizerPlugin : MethodChannel.MethodCallHandler {

    private var engine: Engine? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            "attach" -> result.success(attach(call))
            "setEnabled" -> {
                engine?.setEnabled(call.argument<Boolean>("enabled") ?: true)
                result.success(null)
            }
            "setGains" -> {
                engine?.setGains(call.argument<List<Double>>("gains").orEmpty())
                result.success(null)
            }
            "setGain" -> {
                val index = call.argument<Int>("index") ?: -1
                val gain = call.argument<Double>("gain") ?: 0.0
                engine?.setGain(index, gain)
                result.success(null)
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

        release()
        return try {
            engine = Engine(sessionId, bands, gain)
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

    private class Engine(sessionId: Int, bands: List<Int>, initialGain: Double) {
        private val effect: DynamicsProcessing

        init {
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                CHANNEL_COUNT,
                false,
                PRE_EQ_BANDS,
                false,
                MBC_BANDS,
                true,
                bands.size,
                false,
            ).build()

            effect = DynamicsProcessing(PRIORITY, sessionId, config)

            bands.forEachIndexed { index, hz ->
                try {
                    val band = DynamicsProcessing.EqBand(true, hz.toFloat(), initialGain.toFloat())
                    effect.setPostEqBandAllChannelsTo(index, band)
                } catch (e: Exception) {
                    Log.w(TAG, "Device rejected band $index ($hz Hz)", e)
                }
            }
        }

        fun setEnabled(enabled: Boolean) {
            try {
                effect.enabled = enabled
            } catch (e: Exception) {
                Log.w(TAG, "Unable to toggle equalizer", e)
            }
        }

        fun setGains(gains: List<Double>) {
            gains.forEachIndexed { index, db -> setGain(index, db) }
        }

        fun setGain(index: Int, db: Double) {
            if (index < 0) return
            try {
                val band = effect.getPostEqBandByChannelIndex(0, index)
                band.gain = db.toFloat()
                effect.setPostEqBandAllChannelsTo(index, band)
            } catch (e: Exception) {
                Log.w(TAG, "Unable to set band $index", e)
            }
        }

        fun release() {
            try {
                effect.release()
            } catch (_: Exception) {
                // The effect may already be gone if the audio session ended.
            }
        }
    }

    companion object {
        const val CHANNEL = "pharmaracist.fathom/equalizer"

        private const val TAG = "FathomEqualizer"
        private const val PRIORITY = 0
        private const val CHANNEL_COUNT = 2
        private const val PRE_EQ_BANDS = 0
        private const val MBC_BANDS = 0
    }
}
