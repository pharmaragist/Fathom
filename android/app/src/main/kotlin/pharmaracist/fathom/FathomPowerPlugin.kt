package pharmaracist.fathom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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
            "isIgnoringBatteryOptimizations" ->
                result.success(isIgnoringBatteryOptimizations())
            "requestIgnoreBatteryOptimizations" ->
                result.success(requestIgnoreBatteryOptimizations())
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

    /**
     * Whether Android's battery optimizer is allowed to reclaim Fathom.
     *
     * This is the app-level switch the playback foreground service depends on:
     * a media foreground service survives normal memory pressure, but an OEM
     * power manager that has not exempted the app can still kill the process
     * between tracks. Below API 23 there is no such switch, so the answer is
     * "unrestricted" rather than a permission the user cannot grant.
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        val ctx = context ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return try {
            power.isIgnoringBatteryOptimizations(ctx.packageName)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Opens the system screen that exempts the app from battery optimization.
     *
     * The direct request dialog is the one that actually flips the switch, so it
     * is tried first. OEM builds that do not expose it fall back to the app's own
     * details page, which always has a battery entry; the list of optimized apps
     * is the last resort. Returns whether a screen was opened, not whether the
     * user allowed anything: that answer arrives on the next lifecycle resume,
     * where Dart re-reads [isIgnoringBatteryOptimizations].
     */
    private fun requestIgnoreBatteryOptimizations(): Boolean {
        val ctx = context ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false

        val packageUri = Uri.parse("package:${ctx.packageName}")
        val candidates = if (isIgnoringBatteryOptimizations()) {
            // Already exempt: the useful destination is the list where it can be
            // changed, not a dialog that has nothing left to ask.
            listOf(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } else {
            listOf(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(packageUri),
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(packageUri),
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            )
        }

        for (intent in candidates) {
            try {
                // The Context is the activity, but the intent may outlive it; a
                // new task keeps the system screen independent of the caller.
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try the next destination rather than reporting a dead tap.
            }
        }
        return false
    }

    private fun start() {
        if (receiver != null) return
        val ctx = context ?: return

        val target = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) return
                // The broadcast carries no public extra naming the new state
                // (`EXTRA_POWER_SAVE_MODE` is not part of the SDK), so the value
                // is read back from PowerManager instead of from the intent.
                channel?.invokeMethod("onPowerSaveChanged", isPowerSave())
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
