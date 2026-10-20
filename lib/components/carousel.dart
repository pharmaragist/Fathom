import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../models/tracks.dart';
import 'art.dart';

class CoverCarousel extends StatefulWidget {
  const CoverCarousel({
    super.key,
    required this.isPlaying,
    required this.selectedIndex,
    required this.queue,
    required this.previous,
    required this.next,
    required this.onSkipNext,
    required this.onSkipPrevious,
  });

  final bool isPlaying;
  final int selectedIndex;
  final List<FathomTrack> queue;
  final FathomTrack? previous;
  final FathomTrack? next;
  final Future<void> Function() onSkipNext;
  final Future<void> Function() onSkipPrevious;

  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 26,
  );
  static const _edgeResistance = 0.3;
  static const _neighbourScale = 0.14;
  static const _neighbourFade = 0.5;

  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this);

  double _spacing = 1;

  Object? _idOf(CoverCarousel w) {
    final i = w.selectedIndex;
    if (i < 0 || i >= w.queue.length) return null;
    return w.queue[i].id;
  }

  @override
  void didUpdateWidget(CoverCarousel old) {
    super.didUpdateWidget(old);
    final after = _idOf(widget);
    if (_idOf(old) == after) return;

    var dir = 0;
    if (after != null) {
      if (old.next?.id == after) {
        dir = 1;
      } else if (old.previous?.id == after) {
        dir = -1;
      }
    }

    final velocity = _offset.velocity;
    _offset.value = dir == 0 ? 0 : _offset.value - dir;
    if (_offset.value != 0) _springTo(0, velocity);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _springTo(double target, double velocity) {
    _offset.animateWith(
      SpringSimulation(_spring, _offset.value, target, velocity),
    );
  }

  void _onStart(DragStartDetails d) => _offset.stop();

  void _onUpdate(DragUpdateDetails d) {
    var delta = -d.delta.dx / _spacing;
    final proposed = _offset.value + delta;
    final blocked = (proposed > 0 && widget.next == null) ||
        (proposed < 0 && widget.previous == null);
    if (blocked && proposed.abs() > _offset.value.abs()) {
      delta *= _edgeResistance;
    }
    _offset.value = (_offset.value + delta).clamp(-1.0, 1.0);
  }

  void _onEnd(DragEndDetails d) {
    final velocity = -(d.primaryVelocity ?? 0) / _spacing;
    final projected = _offset.value + velocity * 0.15;

    var dir = 0;
    if (projected > 0.5 && widget.next != null) {
      dir = 1;
    } else if (projected < -0.5 && widget.previous != null) {
      dir = -1;
    }

    _springTo(dir.toDouble(), velocity);
    if (dir != 0) _skip(dir);
  }

  void _onCancel() => _springTo(0, _offset.velocity);

  Future<void> _skip(int dir) async {
    final startId = _idOf(widget);
    try {
      await (dir > 0 ? widget.onSkipNext() : widget.onSkipPrevious());
    } catch (_) {}
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || _idOf(widget) != startId) return;
    _springTo(0, _offset.velocity);
  }

  Widget _empty() {
    return Center(
      child: Icon(
        TablerIcons.music,
        size: 48,
        color: FathomColors.onMedia.withValues(alpha: 0.24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final currentId = _idOf(widget);
    if (currentId == null) return _empty();

    final library = context.read<FathomLibrary>();

    return LayoutBuilder(
      builder: (context, c) {
        final available =
            c.maxHeight < c.maxWidth - 24 ? c.maxHeight - 32 : c.maxWidth - 32;
        final side = available.clamp(120.0, 400.0);
        _spacing = side + 20;

        final used = <String>{};
        Widget card(int slot, FathomTrack track) {
          var key = '${track.id}';
          if (!used.add(key)) key = '$key#$slot';
          return _Card(
            key: ValueKey(key),
            slot: slot,
            offset: _offset,
            spacing: _spacing,
            neighbourScale: _neighbourScale,
            neighbourFade: _neighbourFade,
            child: RepaintBoundary(
              child: _CoverArt(
                track: track,
                side: side,
                isActive: slot == 0,
                isPlaying: widget.isPlaying,
                library: library,
              ),
            ),
          );
        }

        final previous = widget.previous;
        final next = widget.next;
        final current = card(0, queue[widget.selectedIndex]);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          onHorizontalDragCancel: _onCancel,
          child: Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  current,
                  if (previous != null) card(-1, previous),
                  if (next != null) card(1, next),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.slot,
    required this.offset,
    required this.spacing,
    required this.neighbourScale,
    required this.neighbourFade,
    required this.child,
  });

  final int slot;
  final Animation<double> offset;
  final double spacing;
  final double neighbourScale;
  final double neighbourFade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: offset,
      child: child,
      builder: (context, child) {
        final rel = slot - offset.value;
        final t = rel.abs().clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(rel * spacing, 0),
          child: Transform.scale(
            scale: 1 - neighbourScale * t,
            child: Opacity(opacity: 1 - neighbourFade * t, child: child),
          ),
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
    final art = AnimatedScale(
      scale: isPlaying ? 1.0 : 0.9,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: side,
        height: side,
        decoration: BoxDecoration(
          color: FathomColors.mediaSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: FathomColors.shadow
                  .withValues(alpha: isPlaying ? 0.55 : 0.40),
              blurRadius: isPlaying ? 36 : 24,
              offset: Offset(0, isPlaying ? 16 : 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: TrackArt(library: library, track: track, size: side),
        ),
      ),
    );

    return HeroMode(
      enabled: isActive,
      child: Hero(
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
            child: SizedBox.square(dimension: side, child: toHero.child),
          );
        },
        child: art,
      ),
    );
  }
}
