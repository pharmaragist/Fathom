import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:volume_controller/volume_controller.dart';

import '../states.dart';
import '../components/art.dart';
import '../components/glass.dart';

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
    final top = MediaQuery.viewPaddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

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
              padding: EdgeInsets.fromLTRB(0, top + 8, 0, bottom + 16),
              child: Column(
                children: [
                  _Grabber(
                    onTap: () {
                      Navigator.of(context).maybePop();
                    },
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
                          const SizedBox(height: 12),
                          _TitleRow(title: track.title, artist: track.artist),
                          const SizedBox(height: 22),
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
                          const SizedBox(height: 16),
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
    if (!mounted) return;
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
  int _currentPage = 0;
  bool _syncing = false;

  int _maxPage(int len) => len <= 0 ? 0 : len - 1;

  @override
  void initState() {
    super.initState();
    _currentPage =
        widget.selectedIndex.clamp(0, _maxPage(widget.queue.length));
    _controller = PageController(
      initialPage: _currentPage,
      viewportFraction: 1.0,
    );
  }

  @override
  void didUpdateWidget(_CoverCarousel old) {
    super.didUpdateWidget(old);

    final len = widget.queue.length;
    final target = widget.selectedIndex.clamp(0, _maxPage(len));
    final lengthChanged = old.queue.length != len;
    final pageOutOfRange = _currentPage > _maxPage(len);

    if (lengthChanged || pageOutOfRange) {
      _currentPage = target;
      final oldCtrl = _controller;
      _controller = PageController(
        initialPage: target,
        viewportFraction: 1.0,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldCtrl.dispose();
      });
      return;
    }

    if (target != _currentPage) {
      _currentPage = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _syncing = true;
        _controller
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _syncing = false);
      });
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
        final availableH = c.maxHeight.isFinite ? c.maxHeight : 300.0;
        final availableW = c.maxWidth.isFinite ? c.maxWidth : 300.0;
        final side = (availableH < availableW - 24
                ? availableH - 16
                : availableW - 24)
            .clamp(120.0, 420.0)
            .toDouble();

        return PageView.builder(
          controller: _controller,
          itemCount: queue.length,
          physics: const PageScrollPhysics(),
          onPageChanged: (i) {
            _currentPage = i;
            if (_syncing) return;
            widget.onPageChanged(i);
          },
          itemBuilder: (context, i) {
            final track = queue[i];
            final isActive = i == widget.selectedIndex;
            final artSide = side * 0.94;

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
    final art = Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: isActive && isPlaying ? 0.55 : 0.30),
            blurRadius: isActive && isPlaying ? 36 : 20,
            offset: Offset(0, isActive && isPlaying ? 16 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ArtThumb(
          id: track.id,
          artwork: library.artFor(track.id),
          size: side
        ),
      ),
    );

    if (!isActive) return art;

    return Hero(
      tag: 'fathom-art-${track.id}',
      // Keeps the source space occupied so the layout doesn't collapse mid-flight
      placeholderBuilder: (context, heroSize, child) {
        return SizedBox(
          width: heroSize.width,
          height: heroSize.height,
        );
      },
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        final Hero toHero = toHeroContext.widget as Hero;
        return Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              return SizedBox(
                width: side,
                height: side,
                child: toHero.child,
              );
            },
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.3,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
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
                ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble()
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
            _AppleSlider(
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
    final accent = context.watch<FathomSettings>().accent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ModeButton(
          icon: TablerIcons.arrowsShuffle,
          active: player.shuffle,
          accent: accent,
          onTap: () => context.read<FathomPlayer>().toggleShuffle(),
        ),
        _PressFade(
          enabled: player.canSkipPrevious,
          onTap: () => context.read<FathomPlayer>().skipPrevious(),
          child: Icon(
            TablerIcons.playerTrackPrevFilled,
            size: 32,
            color: player.canSkipPrevious ? Colors.white : Colors.white24,
          ),
        ),
        _PressFade(
          onTap: () => context.read<FathomPlayer>().togglePlay(),
          child: Icon(
            player.isPlaying
                ? TablerIcons.playerPauseFilled
                : TablerIcons.playerPlayFilled,
            size: 68,
            color: Colors.white,
          ),
        ),
        _PressFade(
          enabled: player.canSkipNext,
          onTap: () => context.read<FathomPlayer>().skipNext(),
          child: Icon(
            TablerIcons.playerTrackNextFilled,
            size: 32,
            color: player.canSkipNext ? Colors.white : Colors.white24,
          ),
        ),
        _ModeButton(
          icon: _repeatIcon(player.repeatMode),
          active: player.repeatMode != FathomRepeatMode.off,
          accent: accent,
          onTap: () => context.read<FathomPlayer>().cycleRepeat(),
        ),
      ],
    );
  }

  static IconData _repeatIcon(FathomRepeatMode m) {
    switch (m) {
      case FathomRepeatMode.off:
      case FathomRepeatMode.all:
        return TablerIcons.repeat;
      case FathomRepeatMode.one:
        return TablerIcons.repeatOnce;
    }
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressFade(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Icon(
            icon,
            size: 24,
            color: active ? accent : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
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
    } catch (_) {}
    try {
      final v = await VolumeController.instance.getVolume();
      if (!mounted) return;
      setState(() {
        _volume = v.clamp(0.0, 1.0);
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
    try {
      VolumeController.instance.addListener((v) {
        if (!mounted) return;
        setState(() => _volume = v.clamp(0.0, 1.0));
      });
    } catch (_) {}
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
        Icon(
          TablerIcons.volume,
          size: 16,
          color: Colors.white.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AppleSlider(
            value: _volume,
            color: accent,
            enabled: _ready,
            onChanged: _setVolume,
            onChangeEnd: _setVolume,
          ),
        ),
        const SizedBox(width: 10),
        Icon(
          TablerIcons.volume2,
          size: 16,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PressFade(
          onTap: () => showQueueBottomSheet(context),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                TablerIcons.playlist,
                size: 24,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PressFade extends StatefulWidget {
  const _PressFade({
    required this.child,
    required this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_PressFade> createState() => _PressFadeState();
}

class _PressFadeState extends State<_PressFade> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel:
          widget.enabled ? () => setState(() => _down = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedOpacity(
        opacity: _down ? 0.55 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

class _AppleSlider extends StatefulWidget {
  const _AppleSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.color,
    this.onStart,
    this.enabled = true,
  });

  final double value;
  final Color color;
  final bool enabled;
  final VoidCallback? onStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_AppleSlider> createState() => _AppleSliderState();
}

class _AppleSliderState extends State<_AppleSlider> {
  bool _active = false;
  double _last = 0;

  double _ratio(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0).toDouble();

  void _begin(double r) {
    if (!widget.enabled) return;
    widget.onStart?.call();
    _last = r;
    setState(() => _active = true);
    widget.onChanged(r);
  }

  void _update(double r) {
    if (!widget.enabled) return;
    _last = r;
    widget.onChanged(r);
  }

  void _end() {
    if (!widget.enabled) return;
    setState(() => _active = false);
    widget.onChangeEnd(_last);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _begin(_ratio(d.localPosition, w)),
          onTapUp: (_) => _end(),
          onTapCancel: () {
            if (_active) setState(() => _active = false);
          },
          onHorizontalDragStart: (d) => _begin(_ratio(d.localPosition, w)),
          onHorizontalDragUpdate: (d) => _update(_ratio(d.localPosition, w)),
          onHorizontalDragEnd: (_) => _end(),
          child: SizedBox(
            height: 30,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: _active ? 12 : 6,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: widget.value.clamp(0.0, 1.0).toDouble(),
                    child: Container(color: widget.color),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
          child: _QueueSheetContent(),
        ),
      ),
    ),
  );
}

class _QueueSheetContent extends StatelessWidget {
  const _QueueSheetContent();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();
    final accent = context.watch<FathomSettings>().accent;
    final queue = player.queue;
    final current = player.selectedIndex;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Up Next',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    TablerIcons.x,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    onReorder: (from, to) {
                      context.read<FathomPlayer>().moveAt(from, to);
                    },
                    proxyDecorator: (child, index, anim) {
                      return Material(
                        color: Colors.transparent,
                        elevation: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: child,
                        ),
                      );
                    },
                    itemBuilder: (context, i) {
                      final track = queue[i];
                      final isCurrent = i == current;
                      return Material(
                        key: ValueKey('${track.id}_$i'),
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  context.read<FathomPlayer>().playIndex(i);
                                },
                                onLongPress: () {
                                  context.read<FathomPlayer>().removeAt(i);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: isCurrent
                                            ? Icon(
                                                TablerIcons.playerPlayFilled,
                                                size: 16,
                                                color: accent,
                                              )
                                            : Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: isCurrent
                                                    ? accent
                                                    : Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.white
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top: 12,
                                  bottom: 12,
                                ),
                                child: Icon(
                                  TablerIcons.gripVertical,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
