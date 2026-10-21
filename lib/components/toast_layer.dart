import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/settings.dart';
import '../common/toasts.dart';
import 'flat_icon_button.dart';
import 'glass.dart';

/// The shell's toast surface: a stack of glass cards below the page header.
///
/// It lives just under the header and above the pages, so a message never
/// covers the mini player or the nav rail — those are the controls a download
/// message is usually about. The cards are [GlassContainer]s to match every
/// other floating surface in the app, and the newest sits nearest the header,
/// because that is where the eye already is after tapping a track.
///
/// The layer owns its own pointer behaviour rather than being wrapped in an
/// `IgnorePointer` by the shell: a toast is a report, not a control, so it
/// normally takes no taps, but a long-running card carries a close control and
/// that one target has to be reachable. Keeping the decision here means the two
/// cannot disagree.
class FathomToastLayer extends StatefulWidget {
  const FathomToastLayer({super.key});

  @override
  State<FathomToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<FathomToastLayer> {
  /// The toast currently being shown or animating out, newest first.
  ///
  /// This is the layer's own copy rather than `FathomToasts.toasts`, because a
  /// dismissed toast has to stay in the tree long enough to play its exit. Each
  /// entry carries whether it is on its way out.
  final List<_Entry> _entries = <_Entry>[];

  FathomToasts? _toasts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final toasts = context.read<FathomToasts>();
    if (identical(toasts, _toasts)) return;
    _toasts?.removeListener(_onToastsChanged);
    _toasts = toasts..addListener(_onToastsChanged);
    _onToastsChanged();
  }

  @override
  void dispose() {
    _toasts?.removeListener(_onToastsChanged);
    super.dispose();
  }

  /// Rebuilds [_entries] from the notifier, marking disappearances as leaving
  /// instead of dropping them.
  void _onToastsChanged() {
    final live = _toasts?.toasts ?? const <FathomToast>[];
    final liveIds = {for (final toast in live) toast.id};

    // Anything already on screen that is still live keeps its place and takes
    // the notifier's newer copy. Anything no longer live starts leaving.
    for (final entry in _entries) {
      if (liveIds.contains(entry.toast.id)) {
        entry.leaving = false;
      } else {
        entry.leaving = true;
      }
    }

    final known = {for (final entry in _entries) entry.toast.id};
    for (final toast in live.reversed) {
      if (known.contains(toast.id)) continue;
      _entries.add(_Entry(toast: toast));
    }

    // Newest first: the header is where the eye already is.
    _entries.sort((a, b) => b.toast.id.compareTo(a.toast.id));

    if (mounted) setState(() {});
  }

  void _onCardGone(int id) {
    if (!mounted) return;
    setState(() => _entries.removeWhere((entry) => entry.toast.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);

    // The inset clears the status bar and the header row, matching the chrome's
    // own padding, so the first card lands just under the title rather than on
    // top of it.
    final top = MediaQuery.viewPaddingOf(context).top + 56;

    final stack = Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in _entries) ...[
            _ToastCard(
              key: ValueKey(entry.toast.id),
              toast: entry.toast,
              accent: accent,
              leaving: entry.leaving,
              onDismiss: () => _toasts?.dismiss(entry.toast.id),
              onGone: () => _onCardGone(entry.toast.id),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );

    // With nothing to tap the layer stays fully transparent to pointers, so a
    // toast can never steal a tap meant for the list. It only takes hits when a
    // card actually offers a control.
    final takesHits = _entries.any((entry) => entry.toast.dismissible);
    return takesHits ? stack : IgnorePointer(child: stack);
  }
}

/// One card's state: its toast and whether it is on its way out.
class _Entry {
  _Entry({required this.toast});

  final FathomToast toast;
  bool leaving = false;
}

/// One toast card.
///
/// The card leaves the way it arrived: it enters by dropping in from the header
/// and scaling up slightly, and it exits along the same path reversed, so the
/// two ends of its life are one gesture rather than two unrelated effects.
///
/// Motion is short and small on purpose. A toast arrives while the user is
/// reading a list, so it has to be noticed without pulling the eye off whatever
/// they were doing; a large or slow entrance would be an interruption rather
/// than a report. It also respects the platform's reduced-motion setting, which
/// drops the travel and scale and keeps a plain cross-fade — the feedback still
/// arrives, it just stops moving.
class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.toast,
    required this.accent,
    required this.leaving,
    required this.onDismiss,
    required this.onGone,
  });

  final FathomToast toast;
  final Color accent;

  /// Set by the layer once this toast has left the notifier. Drives the exit.
  final bool leaving;

  final VoidCallback onDismiss;

  /// Called once the exit has finished, so the layer can forget the card.
  final VoidCallback onGone;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  );

  /// Enter and exit run mirrored curves, so the card retraces its own path
  /// instead of appearing to leave somewhere else.
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    if (widget.leaving) _reverse();
  }

  @override
  void didUpdateWidget(_ToastCard old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _reverse();
  }

  void _reverse() {
    _controller.reverse().whenComplete(() {
      if (mounted) widget.onGone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The tone's own color: the accent for a confirmation, so a saved download
  /// ties back to the rest of the app, and the status tones for the two
  /// outcomes that have to read as themselves.
  Color get _tone => switch (widget.toast.tone) {
        ToastTone.neutral => widget.accent,
        ToastTone.success => widget.accent,
        ToastTone.failure => FathomColors.error,
      };

  /// The glyph for the tone when the caller did not name one, so an outcome is
  /// recognizable from its shape before its words are read.
  IconData get _icon => switch (widget.toast.tone) {
        ToastTone.neutral => TablerIcons.infoCircle,
        ToastTone.success => TablerIcons.check,
        ToastTone.failure => TablerIcons.alertTriangle,
      };

  @override
  Widget build(BuildContext context) {
    final toast = widget.toast;
    final color = _tone;

    return FadeTransition(
      opacity: _t,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) {
          // With motion reduced the card does not travel or scale; it
          // cross-fades, which keeps the "a message just arrived" feedback
          // without the movement.
          if (MediaQuery.disableAnimationsOf(context)) return child!;
          return Transform.translate(
            // Starts slightly above its resting place and drops in, which reads
            // as arriving from the header.
            offset: Offset(0, -12 * (1 - _t.value)),
            child: Transform.scale(
              scale: 0.98 + 0.02 * _t.value,
              alignment: Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: _shell(toast, color),
      ),
    );
  }

  Widget _shell(FathomToast toast, Color color) {
    return GlassContainer(
      radius: 18,
      accent: color,
      shadow: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The glyph sits on the title's line, not the card's middle: with two
          // lines of text a centred glyph would float between them.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(toast.icon ?? _icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  toast.title,
                  // A title is one line; the detail below is where the length
                  // goes.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: FathomColors.onSurface,
                  ),
                ),
                if (toast.detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    toast.detail!,
                    // A reason runs longer than a confirmation, and this is the
                    // line the user has to read to know what to do, so it is
                    // given room rather than being cut to fit the title's shape.
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w400,
                      color: FathomColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (toast.dismissible) ...[
            const SizedBox(width: 6),
            FlatIconButton(
              icon: TablerIcons.x,
              size: 16,
              color: FathomColors.onSurfaceDim,
              // The glyph is small so it does not compete with the message, but
              // the target a thumb has to hit is not: the padding is what makes
              // the control reachable without making it loud.
              padding: const EdgeInsets.all(6),
              onTap: widget.onDismiss,
            ),
          ],
        ],
      ),
    );
  }
}
