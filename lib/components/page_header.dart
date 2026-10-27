import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/motion.dart';
import '../common/player.dart';
import '../common/selection.dart';
import '../common/settings.dart';
import '../models/tracks.dart';
import '../pages/downloads.dart';
import '../pages/settings.dart';
import '../services/downloads.dart';
import 'flat_icon_button.dart';

/// The title row every main page wears.
///
/// Pages compose their own trailing controls; [shellTrailing] is the set the
/// shell pages share, so a page never re-implements the icons.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: FathomColors.onSurface,
              letterSpacing: -0.8,
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}

/// The library header's controls: selection, downloads, settings and rescan.
///
/// This is the one place the library's trailing controls are defined, so the
/// shell never re-implements them. While [selection] is active the normal
/// controls are replaced rather than extended: the header is describing the
/// selected rows, and leaving download/settings/rescan visible would give the
/// mode two competing sets of actions.
///
/// Select-all covers the *whole* library, read from [FathomLibrary.tracks], not
/// the rows currently on screen. A live search filters those rows, but "all"
/// must keep the meaning the user gave it before searching; narrowing the
/// scope silently would make a batch action skip tracks they never saw leave
/// the selection.
List<Widget> shellTrailing(
  BuildContext context, {
  required FathomSelection selection,
}) {
  final accent = context.read<FathomSettings>().accent;
  final library = context.read<FathomLibrary>();
  // The header listens to the selection, but the select-all glyph also depends
  // on the library's contents. Selecting the snapshot makes this builder
  // depend on a real scan without rebuilding the page body below it.
  final tracks = context.select<FathomLibrary, List<FathomTrack>>(
    (library) => library.tracks,
  );

  if (selection.active) {
    final devices = tracks.where((track) {
      return track.origin == TrackOrigin.device;
    });
    final allSelected =
        devices.isNotEmpty && devices.every(selection.isSelected);
    final selected = [
      for (final track in tracks)
        if (selection.isSelected(track)) track,
    ];

    return [
      FlatIconButton(
        icon: TablerIcons.selectAll,
        size: 22,
        padding: const EdgeInsets.all(8),
        color: allSelected ? accent : FathomColors.onSurface,
        onTap: () => selection.toggleAll(
          context.read<FathomLibrary>().tracks,
        ),
      ),
      FlatIconButton(
        icon: TablerIcons.trash,
        size: 22,
        padding: const EdgeInsets.all(8),
        color: FathomColors.error,
        enabled: selected.isNotEmpty,
        onTap: () => deleteSelectedTracks(context, selection, selected),
      ),
      FlatIconButton(
        icon: TablerIcons.x,
        size: 22,
        padding: const EdgeInsets.all(8),
        color: FathomColors.onSurface,
        onTap: selection.exit,
      ),
    ];
  }

  return [
    FlatIconButton(
      icon: TablerIcons.download,
      size: 22,
      padding: const EdgeInsets.all(8),
      color: FathomColors.onSurface,
      onTap: () =>
          Navigator.of(context).push(utilityRoute(const DownloadsPage())),
    ),
    FlatIconButton(
      icon: TablerIcons.settings,
      size: 22,
      padding: const EdgeInsets.all(8),
      color: FathomColors.onSurface,
      onTap: () => Navigator.of(context).push(settingsRoute()),
    ),
    FlatIconButton(
      icon: TablerIcons.refresh,
      size: 22,
      padding: const EdgeInsets.all(8),
      color: FathomColors.onSurface,
      onTap: () => library.load(grantIfMissing: false),
    ),
  ];
}

/// Deletes the files behind the current selection after one confirmation.
///
/// The platform may show its own confirmation for files Fathom did not create,
/// which is not duplicated here: this dialog is about the library action, the
/// system dialog is about storage access. Only the ids the platform reports as
/// gone leave the selection, so a refused or cancelled row stays selected and
/// can be retried.
Future<void> deleteSelectedTracks(
  BuildContext context,
  FathomSelection selection,
  List<FathomTrack> selected,
) async {
  if (selected.isEmpty) return;
  final count = selected.length;
  final confirmed = await showDialog<bool>(
    context: context,
    animationStyle: kModalMotion,
    builder: (ctx) => AlertDialog(
      backgroundColor: FathomColors.background,
      title: Text(
        count == 1 ? 'Delete track?' : 'Delete $count tracks?',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: FathomColors.onSurface,
        ),
      ),
      content: Text(
        'The ${count == 1 ? 'file' : 'files'} will be removed from this device. '
        'This cannot be undone.',
        style: TextStyle(
          fontSize: 14,
          color: FathomColors.onSurface.withValues(alpha: 0.7),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: FathomColors.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Delete',
            style: TextStyle(
              color: FathomColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final library = context.read<FathomLibrary>();
  final downloads = context.read<FathomDownloads>();
  final player = context.read<FathomPlayer>();

  try {
    final deleted = await library.deleteTracks(selected);
    if (!context.mounted || deleted.isEmpty) return;

    selection.removeDeleted(deleted);
    downloads.forgetMediaIds(deleted);
    await player.forgetTracks(deleted);
  } catch (error) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      animationStyle: kModalMotion,
      builder: (ctx) => AlertDialog(
        backgroundColor: FathomColors.background,
        title: Text(
          'Could not delete',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: FathomColors.onSurface,
          ),
        ),
        content: Text(
          error is PlatformException
              ? (error.message ?? error.code)
              : 'The device did not remove the selected files.',
          style: TextStyle(
            fontSize: 14,
            color: FathomColors.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: FathomColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// The route Settings and Downloads use: a short rise and fade.
///
/// A sideways slide makes a utility page read as a second place in a stack.
/// These pages are not destinations the rail owns, so they should feel like a
/// surface lifting into view over the shell instead of a page being shoved in
/// from the edge. The travel is small enough to read as arrival, not motion.
Route<void> utilityRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 210),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, __, child) {
      // Reduced motion keeps the arrival, minus the travel: a short fade is
      // enough to mark the surface change without moving the page.
      if (MediaQuery.disableAnimationsOf(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      // `drive` rather than a fresh `CurvedAnimation`: the builder runs every
      // frame, and a new curved animation would attach a status listener per
      // frame for the life of the route. The spring curve is critically
      // damped, so the page leaves the way it arrived.
      final curved = animation.drive(
        CurveTween(curve: const FathomSpringCurve()),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Route<void> settingsRoute() => utilityRoute(const SettingsPage());
