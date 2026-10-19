import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:volume_controller/volume_controller.dart';

import '../common/constants.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/art.dart';
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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();
    final track = player.currentTrack;
    final viewPadding = MediaQuery.viewPaddingOf(context);

    if (track == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Nothing playing',
            style: TextStyle(color: Colors.white60),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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
            _BackdropLayer(trackId: track.id),
            Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                viewPadding.top + 8,
                0,
                viewPadding.bottom + 12,
              ),
              child: Column(
                children: [
                  _Grabber(
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    flex: 11,
                    child: _CoverCarousel(
                      isPlaying: player.isPlaying,
                      selectedIndex: player.selectedIndex,
                      queue: player.queue,
                      onPageChanged: (i) {
                        if (i != player.selectedIndex) {
                          player.playIndex(i);
                        }
                      },
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
                            onDragEnd: (r) {
                              final d = player.duration;
                              if (d != null) {
                                player.seekTo(
                                  Duration(
                                    milliseconds:
                                        (r * d.inMilliseconds).round(),
                                  ),
                                );
                              }
                              setState(() => _dragRatio = null);
                            },
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
  const _BackdropLayer({required this.trackId});

  final int trackId;

  @override
  State<_BackdropLayer> createState() => _BackdropLayerState();
}

class _BackdropLayerState extends State<_BackdropLayer> {
  Uint8List? _bytes;
  int _requested = -1;

  @override
  void initState() {
    super.initState();
    _load(widget.trackId);
  }

  @override
  void didUpdateWidget(_BackdropLayer old) {
    super.didUpdateWidget(old);
    if (old.trackId != widget.trackId) {
      _load(widget.trackId);
    }
  }

  Future<void> _load(int id) async {
    if (_requested == id) return;
    _requested = id;
    final lib = context.read<FathomLibrary>();
    final bytes = await lib.artFor(id);
    if (!mounted || _requested != id) return;
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
          const ColoredBox(color: Color(0xFF0E0E10)),
        const ColoredBox(color: Color(0xC2000000)),
      ],
    );
  }
}

class _CoverCarousel extends StatefulWidget {
  const _CoverCarousel({
    required this.isPlaying,
    required this.selectedIndex,
    required this.queue,
    required this.onPageChanged,
  });

  final bool isPlaying;
  final int selectedIndex;
  final List<FathomTrack> queue;
  final ValueChanged<int> onPageChanged;

  @override
  State<_CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<_CoverCarousel> {
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(_CoverCarousel old) {
    super.didUpdateWidget(old);
    if (_controller.hasClients &&
        _controller.page?.round() != widget.selectedIndex) {
      _controller.animateToPage(
        widget.selectedIndex,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.read<FathomLibrary>();
    final queue = widget.queue;

    if (queue.isEmpty) {
      return const Center(
        child: Icon(TablerIcons.music, size: 48, color: Colors.white24),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final rawSide =
            (c.maxHeight < c.maxWidth - 24 ? c.maxHeight - 32 : c.maxWidth - 32)
                .clamp(120.0, 400.0);

        return PageView.builder(
          controller: _controller,
          itemCount: queue.length,
          clipBehavior: Clip.none,
          physics: const PageScrollPhysics(),
          onPageChanged: widget.onPageChanged,
          itemBuilder: (context, i) {
            final track = queue[i];
            final isActive = i == widget.selectedIndex;
            final artSide = rawSide;

            return Center(
              child: AnimatedScale(
                scale: isActive ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: artSide,
                  height: artSide,
                  child: _CoverArt(
                    track: track,
                    side: artSide,
                    isActive: isActive,
                    isPlaying: widget.isPlaying,
                    library: library,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.track,
    required this.side,
    required this.isActive,
    required this.isPlaying,
    required this.library,
  });

  final FathomTrack track;
  final double side;
  final bool isActive;
  final bool isPlaying;
  final FathomLibrary library;

  @override
  Widget build(BuildContext context) {
    final coverScale = isPlaying ? 1.0 : 0.9;

    final art = AnimatedScale(
      scale: coverScale,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: side,
        height: side,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isPlaying ? 0.55 : 0.40),
              blurRadius: isPlaying ? 36 : 24,
              offset: Offset(0, isPlaying ? 16 : 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ArtThumb(
            id: track.id,
            artwork: library.artFor(track.id),
            size: side,
          ),
        ),
      ),
    );

    if (!isActive) return art;

    return Hero(
      tag: 'fathom-art-${track.id}',
      placeholderBuilder: (context, heroSize, child) =>
          SizedBox.fromSize(size: heroSize),
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        final toHero = toHeroContext.widget as Hero;
        return Material(
          type: MaterialType.transparency,
          child: SizedBox.square(
            dimension: side,
            child: toHero.child,
          ),
        );
      },
      child: art,
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
              color: Colors.white.withValues(alpha: 0.35),
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
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Colors.white,
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
            color: Colors.white.withValues(alpha: 0.6),
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
      color: Colors.white.withValues(alpha: 0.5),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return StreamBuilder<Duration>(
      stream: player.audioPlayer.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = player.duration;
        final totalMs = dur?.inMilliseconds ?? 0;
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
          enabled: player.canSkipPrevious,
          onTap: () => context.read<FathomPlayer>().skipPrevious(),
        ),
        FlatIconButton(
          icon: player.isPlaying
              ? TablerIcons.playerPauseFilled
              : TablerIcons.playerPlayFilled,
          size: 64,
          padding: const EdgeInsets.all(8),
          onTap: () => context.read<FathomPlayer>().togglePlay(),
        ),
        FlatIconButton(
          icon: TablerIcons.playerTrackNextFilled,
          size: 32,
          padding: const EdgeInsets.all(8),
          enabled: player.canSkipNext,
          onTap: () => context.read<FathomPlayer>().skipNext(),
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

    return Row(
      children: [
        const SizedBox(width: 30),
        Icon(
          TablerIcons.volume2,
          size: 16,
          color: Colors.white.withValues(alpha: 0.4),
        ),
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
        Icon(
          TablerIcons.volume,
          size: 16,
          color: Colors.white.withValues(alpha: 0.4),
        ),
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FlatIconButton(
          icon: TablerIcons.playlist,
          active: true,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: Colors.white.withValues(alpha: 0.55),
          activeColor: Colors.white,
          onTap: () => showQueueBottomSheet(context),
        ),
        FlatIconButton(
          icon: TablerIcons.arrowsShuffle,
          active: player.shuffle,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: Colors.white.withValues(alpha: 0.55),
          activeColor: accent,
          onTap: () => context.read<FathomPlayer>().toggleShuffle(),
        ),
        FlatIconButton(
          icon: _repeatIcon(player.repeatMode),
          active: player.repeatMode != FathomRepeatMode.off,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: Colors.white.withValues(alpha: 0.55),
          activeColor: accent,
          onTap: () => context.read<FathomPlayer>().cycleRepeat(),
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
    barrierColor: Colors.black.withValues(alpha: 0.55),
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
