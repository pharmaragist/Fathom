import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single equalizer band exposed to the UI.
@immutable
class FathomEqBand {
  const FathomEqBand({
    required this.index,
    required this.centerFrequency,
    required this.minDecibels,
    required this.maxDecibels,
  });

  /// Zero-based position of the band within the active equalizer.
  final int index;

  /// Center frequency in hertz.
  final int centerFrequency;

  /// Lowest gain the band accepts, in decibels.
  final double minDecibels;

  /// Highest gain the band accepts, in decibels.
  final double maxDecibels;
}

/// Bridge to the native fixed ten-band equalizer
/// (`android.media.audiofx.DynamicsProcessing`, API 28+).
///
/// Every method is failure tolerant: if the platform has no ten-band effect,
/// [isSupported] reports `false` and the caller keeps the hardware bands.
class FathomNativeEqualizer {
  static const MethodChannel _channel =
      MethodChannel('pharmaracist.fathom/equalizer');

  /// Gain ceiling of the native stage. Presets peak at +7 dB, so this is ample.
  static const double minDecibels = -12.0;
  static const double maxDecibels = 12.0;

  /// Highest preamp boost the native stage accepts, in decibels.
  static const double maxPreampDecibels = 12.0;

  bool _probed = false;
  bool _supported = false;
  bool _attached = false;

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

  /// Builds the effect on [sessionId] with the given [bands] in hertz.
  Future<bool> attach({
    required int sessionId,
    required List<int> bands,
    double preamp = 0.0,
  }) async {
    if (!await isSupported()) return false;
    try {
      _attached = await _channel.invokeMethod<bool>('attach', <String, Object>{
            'sessionId': sessionId,
            'bands': bands,
            'gain': 0.0,
            'preamp': preamp,
          }) ??
          false;
    } catch (e) {
      debugPrint('Fathom: native equalizer attach failed: $e');
      _attached = false;
    }
    return _attached;
  }

  /// Sets the preamp (input gain) applied before the bands, in decibels.
  Future<void> setPreamp(double db) async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod<void>(
        'setPreamp',
        <String, Object>{'gain': db},
      );
    } catch (e) {
      debugPrint('Fathom: native equalizer preamp update failed: $e');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod<void>(
        'setEnabled',
        <String, Object>{'enabled': enabled},
      );
    } catch (e) {
      debugPrint('Fathom: native equalizer toggle failed: $e');
    }
  }

  Future<void> setGains(List<double> gains) async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod<void>(
        'setGains',
        <String, Object>{'gains': gains},
      );
    } catch (e) {
      debugPrint('Fathom: native equalizer gain update failed: $e');
    }
  }

  Future<void> setGain(int index, double db) async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod<void>(
        'setGain',
        <String, Object>{'index': index, 'gain': db},
      );
    } catch (e) {
      debugPrint('Fathom: native equalizer band update failed: $e');
    }
  }

  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    try {
      await _channel.invokeMethod<void>('detach');
    } catch (e) {
      debugPrint('Fathom: native equalizer detach failed: $e');
    }
  }
}
