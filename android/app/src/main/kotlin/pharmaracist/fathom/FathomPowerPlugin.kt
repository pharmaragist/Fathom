package pharmaracist.fathom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports whether Android's Battery Saver is on.
 *
 * The app forces its low-end rendering mode while the device saves power, and
 * the user is not allowed to turn that off from the settings page. Dart needs
 * two things for that: the current value once at startup, and every later
 * change. The value comes from [PowerManager.isPowerSaveMode]; the changes come
 * from a receiver for [PowerManager.ACTION_POWER_SAVE_MODE_CHANGED].
 *
 * The receiver is only registered between `start` and `stop`, never while the
 * plugin merely exists. It is a system broadcast and so needs no export flag,
 * and keeping it unregistered by default means a Dart caller that never starts
 * (or that goes away) cannot leave a live receiver holding this object in the
 * process. `stop`, and the plugin's own [release], both unregister, so the
 * registration never outlives the subscription that asked for it.
 */
class FathomPowerPlugin(private val context: Context?) :
    MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var receiver: BroadcastReceiver? = null

    /** Points the plugin at the channel it reports changes on. */
    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPowerSave" -> result.success(isPowerSave())
            "start" -> {
                start()
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Unhooks the channel and the receiver. Called when the engine detaches, so
     * a torn-down Flutter engine never leaves a registration behind.
     */
    fun release() {
        stop()
        channel = null
    }

    private fun isPowerSave(): Boolean {
        val ctx = context ?: return false
        val power = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        // A device without a usable PowerManager must read as "not saving
        // power", so Dart can never be wedged into low-end mode by it.
        return try {
            power.isPowerSaveMode
        } catch (e: Exception) {
            false
        }
    }

    private fun start() {
        if (receiver != null) return
        val ctx = context ?: return

        val target = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) return
                val saving = intent.getBooleanExtra(
                    PowerManager.EXTRA_POWER_SAVE_MODE,
                    isPowerSave(),
                )
                channel?.invokeMethod("onPowerSaveChanged", saving)
            }
        }

        try {
            // API 33 requires an explicit export flag on every registration.
            // `RECEIVER_NOT_EXPORTED` is checked against the SDK level rather
            // than used unconditionally so this still compiles on an older
            // `compileSdk`. A system broadcast reaches a not-exported receiver,
            // so refusing other apps is free here.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ctx.registerReceiver(
                    target,
                    IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
                    Context.RECEIVER_NOT_EXPORTED,
                )
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                ctx.registerReceiver(
                    target,
                    IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
                )
            }
            receiver = target
        } catch (e: Exception) {
            // Reporting is best effort: without it Dart keeps whatever value it
            // read at startup rather than losing the bridge entirely.
            receiver = null
        }
    }

    private fun stop() {
        val ctx = context ?: run {
            receiver = null
            return
        }
        val target = receiver ?: return
        receiver = null
        try {
            ctx.unregisterReceiver(target)
        } catch (e: Exception) {
            // Already unregistered, or the context went away first.
        }
    }

    companion object {
        const val CHANNEL = "pharmaracist.fathom/power"
    }
}
