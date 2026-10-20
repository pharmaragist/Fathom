import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Follows Android's Battery Saver state (`PowerManager.isPowerSaveMode`).
///
/// Fathom forces its low-end rendering mode on while the device is saving
/// power, and that mode is not the user's to turn off during that window, so
/// the settings page has to know the device's state as it changes rather than
/// as it was at boot.
///
/// This is a [ChangeNotifier] rather than a bare `ValueListenable<bool>` for one
/// reason: the subscribers are unequal. `FathomApp` has to rebuild its whole
/// subtree when the state flips (it owns the one write of
/// `GlassContainer.blurEnabled`, which does not repaint on its own), while the
/// settings row only needs the flag. A notifier lets the app `addListener` and
/// the row `select` the single field, which a bare listenable could not
/// distinguish.
///
/// Every call is failure tolerant and every failure reads as "not saving
/// power": a channel that is missing (a test host, a platform without the
/// plugin) or a native handler that throws must never wedge the app into
/// low-end mode it cannot leave.
class FathomPowerState extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('pharmaracist.fathom/power');

  bool _powerSave = false;
  bool _started = false;

  /// Whether the device is currently in power-save mode.
  ///
  /// False until the probe answers, and false for any failure, so the boot
  /// value is the safe one.
  bool get isPowerSave => _powerSave;

  /// Reads the current state and starts reporting changes.
  ///
  /// Safe to call more than once: the second call is a no-op, so a widget that
  /// starts this in `initState` cannot stack subscriptions on a rebuild.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_onPlatformCall);
    _powerSave = await _readInitial();
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('start');
    } catch (e) {
      debugPrint('Fathom: power save reporting unavailable: $e');
    }
  }

  /// Stops reporting changes. The last known state is kept, because "we are no
  /// longer listening" is not the same answer as "power save is off".
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('Fathom: could not stop power save reporting: $e');
    }
  }

  @override
  void dispose() {
    // Fire and forget: this runs from `FathomApp`'s dispose, where the engine
    // may already be going away, and nothing needs to await the teardown.
    stop();
    super.dispose();
  }

  Future<bool> _readInitial() async {
    try {
      return await _channel.invokeMethod<bool>('isPowerSave') ?? false;
    } on MissingPluginException {
      // No native side at all (widget tests, desktop). Not saving power.
      return false;
    } catch (e) {
      debugPrint('Fathom: power save probe failed: $e');
      return false;
    }
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    if (call.method != 'onPowerSaveChanged') return;
    // The argument crosses a platform boundary, so a type other than bool
    // means the message is not ours to act on.
    final saving = call.arguments is bool ? call.arguments as bool : false;
    if (saving == _powerSave) return;
    _powerSave = saving;
    notifyListeners();
  }
}
