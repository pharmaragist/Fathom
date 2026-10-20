import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:volume_controller/volume_controller.dart';

import '../common/colors.dart';
import '../common/constants.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/art.dart';
import '../components/carousel.dart';
import '../components/flat_icon_button.dart';
import '../components/flat_slider.dart';
import '../components/glass.dart';
import '../models/tracks.dart';
import '../panels/queue.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  double? _dragRatio;

  void _seekEnd(FathomPlayer player, double ratio) {
    final d = player.duration;
    if (d != null) {
      player.seekTo(Duration(milliseconds: (ratio * d.inMilliseconds).round()));
    }
    setState(() => _dragRatio = null);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();
    final track = player.currentTrack;
    final viewPadding = MediaQuery.viewPaddingOf(context);

    if (track == null) {
      return Scaffold(
        backgroundColor: FathomColors.mediaBackground,
        body: Center(
          child: Text(
            'Nothing playing',
            style: TextStyle(color: FathomColors.onMediaMuted),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: FathomColors.mediaBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 700) {
            Navigator.of(context).maybePop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _BackdropLayer(track: track),
            Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                viewPadding.top + 8,
                0,
                viewPadding.bottom + 12,
              ),
              child: Column(
                children: [
                  _Grabber(onTap: () => Navigator.of(context).maybePop()),
                  Expanded(
                    flex: 11,
                    child: CoverCarousel(
                      isPlaying: player.isPlaying,
                      selectedIndex: player.selectedIndex,
                      queue: player.queue,
                      previous: player.previousTrack,
                      next: player.nextTrack,
                      onSkipNext: player.skipNext,
                      onSkipPrevious: player.skipPrevious,
                    ),
                  ),
                  Expanded(
                    flex: 10,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          _TitleRow(title: track.title, artist: track.artist),
                          const SizedBox(height: 16),
                          _SeekSection(
                            dragRatio: _dragRatio,
                            onDrag: (r) => setState(() => _dragRatio = r),
                            onDragEnd: (r) => _seekEnd(player, r),
                          ),
                          const Spacer(),
                          const _Transport(),
                          const Spacer(),
                          const _VolumeRow(),
                          const SizedBox(height: 12),
                          const _BottomBar(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackdropLayer extends StatefulWidget {
  const _BackdropLayer({required this.track});

  final FathomTrack track;

  @override
  State<_BackdropLayer> createState() => _BackdropLayerState();
}

class _BackdropLayerState extends State<_BackdropLayer> {
  Uint8List? _bytes;
  FathomTrack? _requested;

  @override
  void initState() {
    super.initState();
    _load(widget.track);
  }

  @override
  void didUpdateWidget(_BackdropLayer old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) _load(widget.track);
  }

  Future<void> _load(FathomTrack track) async {
    if (_requested == track) return;
    _requested = track;
    final bytes = await trackArtBytes(context.read<FathomLibrary>(), track);
    if (!mounted || _requested != track) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes != null && bytes.isNotEmpty)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: 360,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            ),
          )
        else
          ColoredBox(color: FathomColors.mediaBackground),
        ColoredBox(color: FathomColors.mediaScrim),
      ],
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 36,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: FathomColors.onMedia.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.artist});

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: FathomColors.onMedia,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.3,
            color: FathomColors.onMediaMuted,
          ),
        ),
      ],
    );
  }
}

class _SeekSection extends StatelessWidget {
  const _SeekSection({
    required this.dragRatio,
    required this.onDrag,
    required this.onDragEnd,
  });

  final double? dragRatio;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();
    final accent = context.watch<FathomSettings>().accent;
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: FathomColors.onMedia.withValues(alpha: 0.5),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return StreamBuilder<Duration>(
      stream: player.audioPlayer.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final totalMs = player.duration?.inMilliseconds ?? 0;
        final ratio = dragRatio ??
            (totalMs > 0
                ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                : 0.0);
        final shownPos = dragRatio != null && totalMs > 0
            ? Duration(milliseconds: (dragRatio! * totalMs).round())
            : pos;
        final remaining = totalMs > 0
            ? Duration(
                milliseconds:
                    (totalMs - shownPos.inMilliseconds).clamp(0, totalMs),
              )
            : null;

        return Column(
          children: [
            FlatSlider(
              value: ratio,
              color: accent,
              enabled: totalMs > 0,
              onChanged: onDrag,
              onChangeEnd: onDragEnd,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(shownPos), style: labelStyle),
                Text(
                  remaining == null ? '--:--' : '-${formatDuration(remaining)}',
                  style: labelStyle,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FlatIconButton(
          icon: TablerIcons.playerTrackPrevFilled,
          size: 32,
          padding: const EdgeInsets.all(8),
          color: FathomColors.onMedia,
          enabled: player.canSkipPrevious,
          onTap: player.skipPrevious,
        ),
        FlatIconButton(
          icon: player.isPlaying
              ? TablerIcons.playerPauseFilled
              : TablerIcons.playerPlayFilled,
          size: 64,
          padding: const EdgeInsets.all(8),
          color: FathomColors.onMedia,
          onTap: player.togglePlay,
        ),
        FlatIconButton(
          icon: TablerIcons.playerTrackNextFilled,
          size: 32,
          padding: const EdgeInsets.all(8),
          color: FathomColors.onMedia,
          enabled: player.canSkipNext,
          onTap: player.skipNext,
        ),
      ],
    );
  }
}

class _VolumeRow extends StatefulWidget {
  const _VolumeRow();

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  double _volume = 1.0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      VolumeController.instance.showSystemUI = false;
      final v = await VolumeController.instance.getVolume();
      if (mounted) {
        setState(() {
          _volume = v.clamp(0.0, 1.0);
          _ready = true;
        });
      }
      VolumeController.instance.addListener((v) {
        if (mounted) setState(() => _volume = v.clamp(0.0, 1.0));
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    try {
      VolumeController.instance.removeListener();
    } catch (_) {}
    super.dispose();
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    try {
      VolumeController.instance.setVolume(v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<FathomSettings>().accent;
    final iconColor = FathomColors.onMedia.withValues(alpha: 0.4);

    return Row(
      children: [
        const SizedBox(width: 30),
        Icon(TablerIcons.volume2, size: 16, color: iconColor),
        const SizedBox(width: 15),
        Expanded(
          child: FlatSlider(
            value: _volume,
            color: accent,
            enabled: _ready,
            onChanged: _setVolume,
            onChangeEnd: _setVolume,
          ),
        ),
        const SizedBox(width: 15),
        Icon(TablerIcons.volume, size: 16, color: iconColor),
        const SizedBox(width: 30),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  static IconData _repeatIcon(FathomRepeatMode m) {
    return switch (m) {
      FathomRepeatMode.off || FathomRepeatMode.all => TablerIcons.repeat,
      FathomRepeatMode.one => TablerIcons.repeatOnce,
    };
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();
    final accent = context.watch<FathomSettings>().accent;
    final idle = FathomColors.onMedia.withValues(alpha: 0.55);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FlatIconButton(
          icon: TablerIcons.playlist,
          active: true,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: idle,
          activeColor: FathomColors.onMedia,
          onTap: () => showQueueBottomSheet(context),
        ),
        FlatIconButton(
          icon: TablerIcons.arrowsShuffle,
          active: player.shuffle,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: idle,
          activeColor: accent,
          onTap: player.toggleShuffle,
        ),
        FlatIconButton(
          icon: _repeatIcon(player.repeatMode),
          active: player.repeatMode != FathomRepeatMode.off,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: idle,
          activeColor: accent,
          onTap: player.cycleRepeat,
        ),
      ],
    );
  }
}

Future<void> showQueueBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: FathomColors.shadow.withValues(alpha: 0.55),
    builder: (ctx) => const Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: GlassContainer(
          radius: 28,
          blur: 12,
          bgOpacity: 0.11,
          borderOpacity: 0.07,
          child: QueuePanel(),
        ),
      ),
    ),
  );
}
