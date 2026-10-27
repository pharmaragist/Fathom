import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native fixed ten-band equalizer
/// (`android.media.audiofx.DynamicsProcessing`, API 28+).
///
/// Every method is failure tolerant: if the platform has no ten-band effect,
/// [isSupported] reports `false` and the caller keeps the hardware bands. Every
/// write reports whether the native stage actually accepted it, because a
/// released effect accepts the call and processes nothing — the caller has to
/// be able to tell that apart from success and re-attach.
class FathomNativeEqualizer {
  static const MethodChannel _channel =
      MethodChannel('pharmaracist.fathom/equalizer');

  /// Gain ceiling of the native stage. Presets peak at +7 dB, so this is ample.
  static const double minDecibels = -12.0;
  static const double maxDecibels = 12.0;

  /// Highest preamp boost the native stage accepts, in decibels.
  static const double maxPreampDecibels = 12.0;

  /// Ceiling the soft limiter holds the processed output under, in dBFS.
  ///
  /// One decibel below digital full scale, which leaves the codec's own
  /// resampling a hair of headroom without audibly lowering the output.
  static const double limiterThresholdDecibels = -1.0;

  /// Compression ratio above [limiterThresholdDecibels].
  ///
  /// 20:1 is steep enough to read as a brick wall on peaks while still being a
  /// limiter rather than a hard clipper.
  static const double limiterRatio = 20.0;

  /// Time the limiter takes to reach its full gain reduction, in milliseconds.
  static const double limiterAttackMilliseconds = 1.0;

  /// Time the limiter takes to let go again, in milliseconds.
  static const double limiterReleaseMilliseconds = 80.0;

  bool _probed = false;
  bool _supported = false;
  bool _attached = false;

  /// Whether this side still believes a native engine is attached.
  ///
  /// False once a write has been refused, which is what tells the player to
  /// rebuild the effect instead of writing into a dead one.
  bool get isAttached => _attached;

  /// Whether the platform exposes a ten-band effect. Result is cached.
  Future<bool> isSupported() async {
    if (_probed) return _supported;
    _probed = true;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e) {
      debugPrint('Fathom: native equalizer probe failed: $e');
      _supported = false;
    }
    return _supported;
  }

  /// Asks the native side whether its engine is still reachable.
  ///
  /// An effect bound to an audio session that the platform has destroyed can
  /// still be held by the bridge while it processes nothing, so this is a
  /// health check the player can run when its surface becomes visible again.
  Future<bool> isAlive() async {
    if (!_attached) return false;
    try {
      final alive = await _channel.invokeMethod<bool>('isAlive') ?? false;
      if (!alive) _attached = false;
      return alive;
    } catch (e) {
      debugPrint('Fathom: native equalizer health check failed: $e');
      _attached = false;
      return false;
    }
  }

  /// Builds the effect on [sessionId] with the given [bands] in hertz.
  ///
  /// [limiter] is the soft peak limiter that rides after the preamp and bands.
  /// It is a safety net, not a loudness stage, and it stays declared in use even
  /// while disabled so [setLimiter] can turn it back on without a rebuild.
  Future<bool> attach({
    required int sessionId,
    required List<int> bands,
    double preamp = 0.0,
    bool limiter = true,
  }) async {
    if (!await isSupported()) return false;
    try {
      _attached = await _channel.invokeMethod<bool>('attach', <String, Object>{
            'sessionId': sessionId,
            'bands': bands,
            'gain': 0.0,
            'preamp': preamp,
            'limiter': limiter,
          }) ??
          false;
    } catch (e) {
      debugPrint('Fathom: native equalizer attach failed: $e');
      _attached = false;
    }
    return _attached;
  }

  /// Enables or bypasses the soft limiter that follows the bands.
  Future<bool> setLimiter(bool enabled) =>
      _write('setLimiter', <String, Object>{'enabled': enabled});

  /// Sets the preamp (input gain) applied before the bands, in decibels.
  Future<bool> setPreamp(double db) =>
      _write('setPreamp', <String, Object>{'gain': db});

  Future<bool> setEnabled(bool enabled) =>
      _write('setEnabled', <String, Object>{'enabled': enabled});

  Future<bool> setGains(List<double> gains) =>
      _write('setGains', <String, Object>{'gains': gains});

  Future<bool> setGain(int index, double db) =>
      _write('setGain', <String, Object>{'index': index, 'gain': db});

  /// Runs one write and reports whether the engine accepted it.
  ///
  /// A refused write is not retried here: the player owns the recovery, because
  /// it is the only place that can rebuild the effect on the current session
  /// and replay the whole curve.
  Future<bool> _write(String method, [Map<String, Object>? arguments]) async {
    if (!_attached) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(method, arguments) ?? false;
      if (!ok) _attached = false;
      return ok;
    } catch (e) {
      debugPrint('Fathom: native equalizer $method failed: $e');
      _attached = false;
      return false;
    }
  }

  Future<void> detach() async {
    _attached = false;
    try {
      await _channel.invokeMethod<void>('detach');
    } catch (e) {
      debugPrint('Fathom: native equalizer detach failed: $e');
    }
  }
}
