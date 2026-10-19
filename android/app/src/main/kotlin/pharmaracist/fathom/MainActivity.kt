package pharmaracist.fathom

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugin = equalizerPlugin ?: FathomEqualizerPlugin().also { equalizerPlugin = it }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FathomEqualizerPlugin.CHANNEL,
        ).setMethodCallHandler(plugin)
    }
}
