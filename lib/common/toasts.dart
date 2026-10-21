import 'dart:async';

import 'package:flutter/widgets.dart';

/// One short-lived message the shell shows below the header.
///
/// A toast is deliberately not a `SnackBar`: the app's bottom edge belongs to
/// the mini player and the nav rail, so a message that appeared there would sit
/// on top of the controls it is reporting about. The shell owns the surface and
/// this is only the message.
///
/// A toast carries up to two lines of text: a [title] that names what happened,
/// and an optional [detail] that explains it. The split exists because the two
/// kinds of message this surface carries are shaped differently — a
/// confirmation is one short clause ("Saved Yesterday"), while a failure is a
/// short clause plus a cause ("Could not save Yesterday" / "YouTube asked for a
/// captcha"). Rendering both as one run of text makes the important half of a
/// failure the part that gets truncated first.
@immutable
class FathomToast {
  const FathomToast({
    required this.id,
    required this.title,
    this.detail,
    this.icon,
    this.tone = ToastTone.neutral,
    this.dismissible = false,
  });

  /// Monotonic identity, so two toasts with the same text are still distinct
  /// entries in the stack and an out-of-order dismissal cannot remove the
  /// wrong one.
  final int id;

  /// The one line that must survive: what happened.
  final String title;

  /// The explanation, when there is one worth reading. Never a restatement of
  /// [title].
  final String? detail;

  /// Optional leading glyph, e.g. a download arrow while work is in flight.
  final IconData? icon;

  final ToastTone tone;

  /// Whether the card offers its own close control.
  ///
  /// Off for the ordinary short-lived message, which the user has no reason to
  /// dismiss early and which would only gain a target to miss. On for a
  /// long-running one — a download in flight — because the alternative is a
  /// message the user cannot get rid of if the work outlives its usefulness.
  /// The toast layer is wrapped in an `IgnorePointer`, so a card that is not
  /// dismissible cannot be interacted with at all; this flag is what decides
  /// whether the layer lets taps through to that one control.
  final bool dismissible;
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
  /// How many toasts may be on screen at once.
  ///
  /// A stack of glass cards is a surface that stops being readable well before
  /// it stops fitting, and the messages are unrelated to each other, so there
  /// is nothing to compare past a couple. When the cap is exceeded the oldest
  /// is dropped rather than the queue being held back: a toast is a report
  /// about the recent past, so the newest is the one worth keeping.
  static const int maxVisible = 3;

  final List<FathomToast> _toasts = [];
  int _nextId = 0;
  bool _disposed = false;

  /// The pending auto-dismiss timers, keyed by toast id.
  ///
  /// Tracked rather than left as loose `Future.delayed` callbacks so they can be
  /// cancelled when a toast leaves for another reason. Without that, clearing
  /// the queue or tearing the shell down leaves a timer scheduled against a
  /// message that is already gone, which keeps the app awake for a report
  /// nobody will see and trips the test framework's pending-timer check.
  final Map<int, Timer> _timers = <int, Timer>{};

  /// The toasts on screen, oldest first. The newest sits nearest the header.
  List<FathomToast> get toasts => List.unmodifiable(_toasts);

  /// Shows a message and returns its identity.
  ///
  /// The caller may pass [duration] to keep a long-running message ("Downloading
  /// X") on screen for the length of the work; the default suits a one-line
  /// confirmation. Pass [dismissible] with a long one, so the user is not stuck
  /// with it if it outlives its usefulness.
  int show(
    String title, {
    String? detail,
    IconData? icon,
    ToastTone tone = ToastTone.neutral,
    Duration duration = const Duration(seconds: 3),
    bool dismissible = false,
  }) {
    final id = _nextId++;
    _toasts.add(FathomToast(
      id: id,
      title: title,
      detail: detail,
      icon: icon,
      tone: tone,
      dismissible: dismissible,
    ));

    while (_toasts.length > maxVisible) {
      _toasts.removeAt(0);
    }
    notifyListeners();

    // Auto-dismiss. `dismiss` is idempotent, so a toast the caller removes
    // first simply makes this a no-op rather than an error; the timer is
    // tracked so that case cancels it instead of leaving it scheduled.
    _timers[id]?.cancel();
    _timers[id] = Timer(duration, () => dismiss(id));
    return id;
  }

  /// Removes [id] if it is still showing. Safe to call for an id that has
  /// already gone.
  void dismiss(int id) {
    // Cancelled even when disposed: the timer must not stay scheduled.
    _timers.remove(id)?.cancel();
    if (_disposed) return;
    final before = _toasts.length;
    _toasts.removeWhere((toast) => toast.id == id);
    if (_toasts.length != before) notifyListeners();
  }

  /// Clears everything. The shell uses this when it is torn down, so a pending
  /// auto-dismiss cannot fire against a disposed tree.
  void clear() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (_toasts.isEmpty) return;
    _toasts.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
