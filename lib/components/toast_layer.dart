import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/settings.dart';
import '../common/toasts.dart';
import 'glass.dart';

/// The shell's toast surface: a stack of glass cards below the page header.
///
/// It lives just under the header and above the pages, so a message never
/// covers the mini player or the nav rail — those are the controls a download
/// message is usually about. The cards are [GlassContainer]s to match every
/// other floating surface in the app, and the newest sits nearest the header,
/// because that is where the eye already is after tapping a track.
///
/// The layer is wrapped in an [IgnorePointer] by the shell: a toast is a
/// report, never a control, so it must not steal a tap from the page beneath.
class FathomToastLayer extends StatelessWidget {
  const FathomToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);

    return Consumer<FathomToasts>(
      builder: (context, toasts, _) {
        // The inset clears the status bar and the header row, matching the
        // chrome's own padding, so the first card lands just under the title
        // rather than on top of it.
        final top = MediaQuery.viewPaddingOf(context).top + 56;

        return Padding(
          padding: EdgeInsets.fromLTRB(20, top, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final toast in toasts.toasts.reversed) ...[
                _ToastCard(toast: toast, accent: accent),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One toast card. Enters with a short slide-and-fade so a message arriving
/// mid-scroll is noticed without being abrasive.
class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.toast, required this.accent});

  final FathomToast toast;
  final Color accent;

  /// The tone's own color: the accent for a confirmation, so a saved download
  /// ties back to the rest of the app, and the status tones for the two
  /// outcomes that have to read as themselves.
  Color get _tone => switch (toast.tone) {
        ToastTone.neutral => accent,
        ToastTone.success => accent,
        ToastTone.failure => FathomColors.error,
      };

  @override
  Widget build(BuildContext context) {
    final color = _tone;

    return TweenAnimationBuilder<double>(
      // Keyed by identity, so each toast animates in on its own rather than
      // every card replaying whenever the list changes.
      key: ValueKey(toast.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        // Starts slightly above its resting place and drops in, which reads as
        // arriving from the header.
        offset: Offset(0, -12 * (1 - t)),
        child: Opacity(opacity: t, child: child),
      ),
      child: GlassContainer(
        radius: 18,
        accent: color,
        shadow: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(
              toast.icon ?? TablerIcons.infoCircle,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                toast.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: FathomColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
