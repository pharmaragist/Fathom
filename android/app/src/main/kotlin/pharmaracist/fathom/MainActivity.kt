package pharmaracist.fathom

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI on audio_service's shared engine so that
 * [com.ryanheise.audioservice.AudioService] can reach the playback handler that
 * lives in the app isolate. Without this superclass the media notification is
 * never posted.
 */
class MainActivity : AudioServiceActivity() {
    private var equalizerPlugin: FathomEqualizerPlugin? = null
    private var downloadsPlugin: FathomDownloadsPlugin? = null
    private var powerPlugin: FathomPowerPlugin? = null
    private var libraryPlugin: FathomLibraryPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugin = equalizerPlugin ?: FathomEqualizerPlugin().also { equalizerPlugin = it }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FathomEqualizerPlugin.CHANNEL,
        ).setMethodCallHandler(plugin)

        // Downloads need a Context to reach ContentResolver with, so the
        // plugin is wired to this activity instead of creating its own.
        val downloads = downloadsPlugin
            ?: FathomDownloadsPlugin(this).also { downloadsPlugin = it }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FathomDownloadsPlugin.CHANNEL,
        ).setMethodCallHandler(downloads)

        // Deleting a library track is a MediaStore request, and on Android 11
        // and later it may need the activity to host the system's delete
        // confirmation. The answer is forwarded back below.
        val library = libraryPlugin
            ?: FathomLibraryPlugin(this).also { libraryPlugin = it }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FathomLibraryPlugin.CHANNEL,
        ).setMethodCallHandler(library)

        // Power save mode is a device state the UI has to follow live, so the
        // plugin reports back on this same channel instead of being polled. It
        // is given this activity as its Context, and handed the channel so the
        // broadcast it registers while started has somewhere to report.
        val power = powerPlugin ?: FathomPowerPlugin(this).also { powerPlugin = it }
        val powerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FathomPowerPlugin.CHANNEL,
        )
        power.attach(powerChannel)
        powerChannel.setMethodCallHandler(power)
    }

    /**
     * Releases the power plugin's broadcast receiver with the engine. The
     * plugin only holds one while Dart has it started, and this is the
     * backstop for a Dart side that never gets to call `stop`.
     */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        powerPlugin?.release()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        downloadsPlugin?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        libraryPlugin?.onActivityResult(requestCode, resultCode, data)
    }
}
