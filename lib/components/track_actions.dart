import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../common/toasts.dart';
import '../models/tracks.dart';
import '../services/downloads.dart';
import 'glass.dart';

/// The per-track menu every surface offers: play it now, put it next, append
/// it, and for a remote track, keep it.
///
/// Everything that only needs a provider is done here. Playing is different:
/// a track plays in the context of the list it came from, so the caller passes
/// [onPlay] and the menu just reports the choice.
Future<void> showTrackActions(
  BuildContext context,
  FathomTrack track, {
  required VoidCallback onPlay,
}) async {
  final accent = context.read<FathomSettings>().accent;
  final result = await showModalBottomSheet<_TrackAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: FathomColors.scrim,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: GlassContainer(
          radius: 28,
          accent: accent,
          shadow: true,
          child: _ActionSheet(track: track, accent: accent),
        ),
      ),
    ),
  );
  if (result == null) return;

  if (!context.mounted) return;
  switch (result) {
    case _TrackAction.play:
      onPlay();
    case _TrackAction.playNext:
      await context.read<FathomPlayer>().playNext([track]);
    case _TrackAction.addToQueue:
      await context.read<FathomPlayer>().enqueue([track]);
    case _TrackAction.download:
      await _runDownload(context, track);
  }
}

enum _TrackAction { play, playNext, addToQueue, download }

Future<void> _runDownload(BuildContext context, FathomTrack track) async {
  final toasts = context.read<FathomToasts>();
  final title = track.title;

  // A pending message rather than a bar at the bottom: the rail and the mini
  // player own that edge, and a download is usually started from a row that is
  // near the top of the list, so the message belongs where the eye already is.
  final pending = toasts.show(
    'Downloading $title',
    icon: TablerIcons.cloudDownload,
    // Held for the length of the fetch, and replaced by the outcome below.
    duration: const Duration(minutes: 5),
  );

  final ok = await context.read<FathomDownloads>().download(track);
  toasts.dismiss(pending);
  toasts.show(
    ok ? 'Saved $title' : 'Could not save $title',
    icon: ok ? TablerIcons.check : TablerIcons.alertTriangle,
    tone: ok ? ToastTone.success : ToastTone.failure,
  );
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.track, required this.accent});

  final FathomTrack track;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<FathomDownloads>();
    final state = downloads.stateOf(track.videoId);
    final canDownload = track.videoId != null && state != DownloadState.done;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: FathomColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: FathomColors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          _ActionRow(
            icon: TablerIcons.playerPlay,
            label: 'Play now',
            accent: accent,
            onTap: () => Navigator.of(context).pop(_TrackAction.play),
          ),
          _ActionRow(
            icon: TablerIcons.playerSkipForward,
            label: 'Play next',
            accent: accent,
            onTap: () => Navigator.of(context).pop(_TrackAction.playNext),
          ),
          _ActionRow(
            icon: TablerIcons.playlistAdd,
            label: 'Add to queue',
            accent: accent,
            onTap: () => Navigator.of(context).pop(_TrackAction.addToQueue),
          ),
          if (canDownload)
            switch (state) {
              DownloadState.pending || DownloadState.running => _ActionProgress(
                  progress: downloads.progressOf(track.videoId),
                  queued: state == DownloadState.pending,
                  accent: accent,
                ),
              DownloadState.failed => _ActionRow(
                  icon: TablerIcons.alertTriangle,
                  label: 'Download failed — retry',
                  accent: accent,
                  onTap: () => Navigator.of(context).pop(_TrackAction.download),
                ),
              _ => _ActionRow(
                  icon: TablerIcons.download,
                  label: 'Download',
                  accent: accent,
                  onTap: () => Navigator.of(context).pop(_TrackAction.download),
                ),
            },
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
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

/// The download row while it is working: progress instead of an action, since
/// pressing it again would do nothing.
class _ActionProgress extends StatelessWidget {
  const _ActionProgress({
    required this.progress,
    required this.queued,
    required this.accent,
  });

  final double progress;
  final bool queued;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                queued ? TablerIcons.clock : TablerIcons.cloudDownload,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  queued
                      ? 'Waiting its turn'
                      : 'Downloading ${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: FathomColors.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          if (!queued) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: FathomColors.onSurface.withValues(alpha: 0.12),
                color: accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
