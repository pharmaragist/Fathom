import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/motion.dart';
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
    this.progress,
  });

  final bool isPlaying;
  final int selectedIndex;
  final List<FathomTrack> queue;
  final FathomTrack? previous;
  final FathomTrack? next;
  final Future<void> Function() onSkipNext;
  final Future<void> Function() onSkipPrevious;

  /// Optional mirror of the deck's live offset, in slots.
  ///
  /// Now Playing puts its title and artist under the covers, outside this
  /// widget's box, and wants them to travel with the art. The spring lives
  /// here, so this is the one place that can publish it: the state writes
  /// every offset change into [progress] and a sibling listens. It is a
  /// notifier rather than a builder callback because the sibling is laid out
  /// adjacent to the deck, not inside it, and only that sibling should rebuild
  /// per frame — the page must not.
  final ValueNotifier<double>? progress;

  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel>
    with SingleTickerProviderStateMixin {
  static const _spring = FathomMotion.momentum;
  static const _edgeResistance = 0.3;
  static const _neighbourScale = 0.14;
  static const _neighbourFade = 0.5;

  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this);

  double _spacing = 1;

  @override
  void initState() {
    super.initState();
    _offset.addListener(_publishProgress);
  }

  /// Carries the live offset to [CoverCarousel.progress] so a sibling can move
  /// with the deck. Writing the notifier does not rebuild this subtree — the
  /// cards listen to the controller directly — so the only cost is the
  /// listener's own rebuild of whatever elected to watch it.
  ///
  /// The one subtlety is *when* a change happens. Most come from the spring
  /// ticking between frames, but a skip also snaps the controller from
  /// `didUpdateWidget`, which runs during build. Marking a sibling's listeners
  /// dirty there would be a build-phase write, so that case is deferred to the
  /// end of the frame; the deck is then one frame behind for a single frame,
  /// which is invisible next to the spring it is joining.
  void _publishProgress() {
    final progress = widget.progress;
    if (progress == null) return;
    if (progress.value == _offset.value) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) progress.value = _offset.value;
      });
      return;
    }
    progress.value = _offset.value;
  }

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
    _offset.removeListener(_publishProgress);
    _offset.dispose();
    super.dispose();
  }

  void _springTo(double target, double velocity) {
    _offset.animateWith(
      _spring.simulation(from: _offset.value, to: target, velocity: velocity),
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
    // The Hero wraps the scale, not the other way round. Its flight rectangle
    // is the card's full square; nesting it inside the pause/play scale made
    // the destination a different size whenever playback was paused.
    final artwork = SpringValue(
      value: isPlaying ? 1.0 : 0.0,
      spring: FathomMotion.gentle,
      builder: (context, t) {
        // Scale and shadow share one spring so the cover does not grow while
        // its depth arrives late: playback reads as one material change.
        final scale = 0.9 + 0.1 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: FathomColors.mediaSurface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: FathomColors.shadow.withValues(alpha: 0.40 + 0.15 * t),
                  blurRadius: 24 + 12 * t,
                  offset: Offset(0, 10 + 6 * t),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: TrackArt(library: library, track: track, size: side),
            ),
          ),
        );
      },
    );

    // Only the active card carries a tag. The side covers are a peek at what
    // a skip would reach, not destinations of their own, and two tagged copies
    // of the same track would make the flight ambiguous.
    if (!isActive) return artwork;

    return Hero(
      tag: 'fathom-art-${track.id}',
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        // Read the destination child rather than rebuilding it, and pin the
        // shuttle to the card's full square so a paused 0.9 scale cannot shrink
        // the flight on the way in.
        final toHero = toHeroContext.widget as Hero;
        return Material(
          type: MaterialType.transparency,
          child: SizedBox.square(
            dimension: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: toHero.child,
            ),
          ),
        );
      },
      child: artwork,
    );
  }
}
