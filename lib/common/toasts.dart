import 'package:flutter/widgets.dart';

/// One short-lived message the shell shows below the header.
///
/// A toast is deliberately not a `SnackBar`: the app's bottom edge belongs to
/// the mini player and the nav rail, so a message that appeared there would sit
/// on top of the controls it is reporting about. The shell owns the surface and
/// this is only the message.
@immutable
class FathomToast {
  const FathomToast({
    required this.id,
    required this.message,
    this.icon,
    this.tone = ToastTone.neutral,
  });

  /// Monotonic identity, so two toasts with the same text are still distinct
  /// entries in the stack and an out-of-order dismissal cannot remove the
  /// wrong one.
  final int id;

  final String message;

  /// Optional leading glyph, e.g. a download arrow while work is in flight.
  final IconData? icon;

  final ToastTone tone;
}

/// How a toast reads. Drives its accent, not its layout.
enum ToastTone { neutral, success, failure }

/// The shell's queue of visible toasts.
///
/// Deliberately tiny and in-memory: a toast reports something that just
/// happened, so it has no state worth persisting and no reason to outlive the
/// screen it was raised on. Anything that does need to survive (a failed
/// download, a broken remote search) already lives on the service that owns it,
/// and the toast is only the announcement.
class FathomToasts extends ChangeNotifier {
  final List<FathomToast> _toasts = [];
  int _nextId = 0;

  /// The toasts on screen, oldest first. The newest sits nearest the header.
  List<FathomToast> get toasts => List.unmodifiable(_toasts);

  /// Shows a message and returns its identity.
  ///
  /// The caller may pass [duration] to keep a long-running message ("Downloading
  /// X") on screen for the length of the work; the default suits a one-line
  /// confirmation.
  int show(
    String message, {
    IconData? icon,
    ToastTone tone = ToastTone.neutral,
    Duration duration = const Duration(seconds: 3),
  }) {
    final id = _nextId++;
    _toasts.add(FathomToast(
      id: id,
      message: message,
      icon: icon,
      tone: tone,
    ));
    notifyListeners();

    // Auto-dismiss. The timer is intentionally not tracked per toast: `dismiss`
    // is idempotent, so a toast the caller removes first simply makes this a
    // no-op rather than an error.
    Future<void>.delayed(duration, () => dismiss(id));
    return id;
  }

  /// Removes [id] if it is still showing. Safe to call for an id that has
  /// already gone.
  void dismiss(int id) {
    final before = _toasts.length;
    _toasts.removeWhere((toast) => toast.id == id);
    if (_toasts.length != before) notifyListeners();
  }

  /// Clears everything. The shell uses this when it is torn down, so a pending
  /// auto-dismiss cannot fire against a disposed tree.
  void clear() {
    if (_toasts.isEmpty) return;
    _toasts.clear();
    notifyListeners();
  }
}
