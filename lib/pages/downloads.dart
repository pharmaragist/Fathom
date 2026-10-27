import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/art.dart';
import '../components/flat_icon_button.dart';
import '../components/sticky_header.dart';
import '../models/tracks.dart';
import '../services/downloads.dart';
import 'library.dart' show nowPlayingRoute;

/// What Fathom has fetched.
///
/// Three kinds of record live here, and only two of them belong to the
/// download service: the files that are on the device, the work still running,
/// and the attempts that failed. A finished file is an ordinary device track,
/// so the library owns it; what the service still owes the user — the queued
/// download, the running one, the failure with its reason — is what only the
/// service can answer.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  /// Plays a downloaded track in the context of the list it came from.
  ///
  /// The same shape the library uses: the queue is the list on screen, and a
  /// track that will not start pops the page it was opened from rather than
  /// leaving the user looking at a player that is not playing.
  void _play(BuildContext context, List<FathomTrack> tracks, int index) {
    final player = context.read<FathomPlayer>();
    final navigator = Navigator.of(context);
    final started = player.playFrom(tracks, index);
    navigator.push(nowPlayingRoute());
    started.then((ok) {
      if (ok || !navigator.mounted) return;
      try {
        navigator.maybePop();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final entries = context.select<FathomDownloads, List<DownloadEntry>>(
      (d) => d.entries,
    );
    final mediaIds = context.select<FathomDownloads, List<int>>(
      (d) => d.downloadedMediaIds,
    );
    final libraryTracks =
        context.select<FathomLibrary, List<FathomTrack>>((l) => l.tracks);

    // The manifest says which files are ours; the library says what they are
    // called and what they look like. A file the scan has not found yet is not
    // listed — it is on the device, but nothing can say what it is.
    final byId = {for (final track in libraryTracks) track.id: track};
    final downloaded = <FathomTrack>[
      for (final id in mediaIds.reversed)
        if (byId[id] != null) byId[id]!,
    ];

    final running = <DownloadEntry>[];
    final failed = <DownloadEntry>[];
    for (final entry in entries) {
      switch (entry.state) {
        case DownloadState.pending || DownloadState.running:
          running.add(entry);
        case DownloadState.failed:
          failed.add(entry);
        case DownloadState.idle || DownloadState.done:
          break;
      }
    }

    final viewPadding = MediaQuery.viewPaddingOf(context);
    final empty = running.isEmpty && failed.isEmpty && downloaded.isEmpty;

    return Scaffold(
      backgroundColor: FathomColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPageHeader(
            title: 'Downloads',
            topInset: viewPadding.top,
            trailing: FlatIconButton(
              icon: TablerIcons.x,
              size: 24,
              padding: const EdgeInsets.all(8),
              color: FathomColors.onSurface,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (empty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyDownloads(),
            )
          else ...[
            if (running.isNotEmpty) ...[
              const SliverSectionLabel(label: 'In progress', top: 8),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    for (final entry in running)
                      _InFlightRow(entry: entry, accent: accent),
                  ]),
                ),
              ),
            ],
            if (failed.isNotEmpty) ...[
              const SliverSectionLabel(label: 'Failed'),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    for (final entry in failed)
                      _FailedRow(entry: entry, accent: accent),
                  ]),
                ),
              ),
            ],
            if (downloaded.isNotEmpty) ...[
              const SliverSectionLabel(label: 'On this device'),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    for (var i = 0; i < downloaded.length; i++)
                      _DeviceRow(
                        track: downloaded[i],
                        accent: accent,
                        onTap: () => _play(context, downloaded, i),
                      ),
                  ]),
                ),
              ),
            ],
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: viewPadding.bottom + 24),
          ),
        ],
      ),
    );
  }
}

/// A download that is queued or running.
///
/// The progress is read here rather than taken from the entry: a running
/// download reports progress constantly, and only this row has to answer for
/// it.
class _InFlightRow extends StatelessWidget {
  const _InFlightRow({required this.entry, required this.accent});

  final DownloadEntry entry;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<FathomDownloads, double>(
      (d) => d.progressOf(entry.videoId),
    );
    final queued = entry.state == DownloadState.pending;
    final library = context.read<FathomLibrary>();

    return _Row(
      art: TrackArt(
        library: library,
        track: entry.track,
        size: 46,
        radius: 12,
      ),
      title: entry.track.title,
      subtitle: queued
          ? 'Waiting its turn'
          : 'Downloading ${(progress * 100).round()}%',
      trailing: queued
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: accent,
              ),
            )
          : SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                color: accent,
              ),
            ),
    );
  }
}

/// A download that failed.
///
/// The reason is on the row, not behind a tap: the causes are not
/// interchangeable — a captcha is worth retrying later, a video with no audio
/// stream never will be — so the row says which one it was and offers the
/// retry.
class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.entry, required this.accent});

  final DownloadEntry entry;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final library = context.read<FathomLibrary>();
    final downloads = context.read<FathomDownloads>();

    return _Row(
      art: TrackArt(
        library: library,
        track: entry.track,
        size: 46,
        radius: 12,
      ),
      title: entry.track.title,
      subtitle: entry.failure ?? 'Could not save this track',
      subtitleColor: FathomColors.error,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlatIconButton(
            icon: TablerIcons.refresh,
            size: 20,
            padding: const EdgeInsets.all(6),
            color: accent,
            onTap: () => downloads.download(entry.track),
          ),
          FlatIconButton(
            icon: TablerIcons.x,
            size: 18,
            padding: const EdgeInsets.all(6),
            color: FathomColors.onSurfaceFaint,
            onTap: () => downloads.forget(entry.videoId),
          ),
        ],
      ),
    );
  }
}

/// A file Fathom has fetched, now an ordinary track on the device.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.track,
    required this.accent,
    required this.onTap,
  });

  final FathomTrack track;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final library = context.read<FathomLibrary>();
    final playing = context.select<FathomPlayer, bool>(
      (p) => p.currentTrack?.id == track.id,
    );

    return _Row(
      // No Hero here: the cover does not morph into Now Playing from this
      // page. The library owns that transition; here the page is pushed
      // plainly, so both covers can coexist without a matching-tag flight.
      art: TrackArt(
        library: library,
        track: track,
        size: 46,
        radius: 12,
      ),
      title: track.title,
      titleColor: playing ? accent : null,
      subtitle: track.artist,
      onTap: onTap,
    );
  }
}

/// One row of the list: art, a title, a line under it, and a control.
class _Row extends StatelessWidget {
  const _Row({
    required this.art,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  final Widget art;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              art,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: titleColor ?? FathomColors.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          color: subtitleColor ?? FathomColors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TablerIcons.cloudDownload,
              size: 40,
              color: FathomColors.onSurfaceFaint,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing downloaded yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Search YouTube from the library and tap a result to keep it on '
              'this device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: FathomColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
