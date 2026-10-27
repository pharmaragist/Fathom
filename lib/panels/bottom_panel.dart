import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/motion.dart';
import '../common/player.dart';
import '../common/search.dart';
import '../common/settings.dart';
import '../components/art.dart';
import '../components/flat_icon_button.dart';
import '../components/glass.dart';
import '../components/nav_rail.dart';
import '../components/track_text_morph.dart';
import '../content.dart' show ShellPage;
import '../models/tracks.dart';
import '../pages/library.dart'
    show chooseSortBottomSheet, LibrarySort, nowPlayingRoute;

class BottomPanel extends StatelessWidget {
  const BottomPanel({
    super.key,
    required this.searchController,
    required this.onSearchOpenChanged,
    required this.page,
    required this.onGoTo,
  });

  final TextEditingController searchController;

  /// Reports the expanded state of the search rail to the shell, which owns
  /// the dismiss layer sitting between the page and this panel.
  final ValueChanged<bool> onSearchOpenChanged;

  /// The destination on screen, which the rail highlights from.
  final ValueListenable<ShellPage> page;

  /// Moves the shell to another destination.
  final ValueChanged<ShellPage> onGoTo;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final sortIndex = context.select<FathomSettings, int>(
      (s) => s.get<int>(SettingKey.sortIndex),
    );
    final currentSort =
        LibrarySort.values[sortIndex.clamp(0, LibrarySort.values.length - 1)];

    final search = context.watch<FathomSearch>();
    // Ordering means nothing once a query is live: results are matches, not a
    // browsable list.
    final sorting = search.query.value.trim().isEmpty;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Consumer<FathomSettings>(
            builder: (context, settings, _) => FloatingNavRail(
              accent: settings.accent,
              bottomSafe: bottomSafe,
              searchController: searchController,
              query: search.query,
              onSearchChanged: (q) => search.query.value = q,
              onSearchOpenChanged: onSearchOpenChanged,
              onSearchCleared: search.clear,
              page: page,
              onGoTo: onGoTo,
              sortLabel: sorting ? currentSort.label : null,
              onSort: !sorting
                  ? null
                  : () => chooseSortBottomSheet(
                        context,
                        settings.accent,
                        currentSort,
                      ),
            ),
          ),
        ),
        Positioned(
          left: kHorizontalMargin,
          right: kHorizontalMargin,
          bottom: bottomSafe + kNavBarHeight + kElevationMargin,
          child: FloatingIslandPlayer(),
        ),
      ],
    );
  }
}

class FloatingIslandPlayer extends StatelessWidget {
  const FloatingIslandPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final hasCurrent = context.select<FathomPlayer, bool>(
      (player) => player.hasCurrent,
    );
    if (!hasCurrent) return const SizedBox.shrink();

    final track = context.select<FathomPlayer, FathomTrack?>(
      (player) => player.currentTrack,
    );
    final previous = context.select<FathomPlayer, FathomTrack?>(
      (player) => player.previousTrack,
    );
    final next = context.select<FathomPlayer, FathomTrack?>(
      (player) => player.nextTrack,
    );
    final isPlaying = context.select<FathomPlayer, bool>(
      (player) => player.isPlaying,
    );
    final library = context.read<FathomLibrary>();
    final player = context.read<FathomPlayer>();
    if (track == null) return const SizedBox.shrink();

    return _PillArrival(
      child: GlassContainer(
        radius: kPillHeight / 2,
        bgOpacity: 0.11,
        borderOpacity: 0.07,
        shadow: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: _PillProgress(player: player),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _PillCards(
                      track: track,
                      previous: previous,
                      next: next,
                      library: library,
                      onOpen: () {
                        // No flight from the pill: the tags belong to the
                        // library rows and the Now Playing destination.
                        Navigator.of(context).push(nowPlayingRoute());
                      },
                      onSkipNext: player.skipNext,
                      onSkipPrevious: player.skipPrevious,
                    ),
                  ),
                  FlatIconButton(
                    icon: isPlaying
                        ? TablerIcons.playerPauseFilled
                        : TablerIcons.playerPlayFilled,
                    onTap: player.togglePlay,
                    padding: const EdgeInsets.all(4),
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

/// The mini player arriving when a first track starts.
///
/// It enters from slightly below and slightly small, on the gentle spring, so
/// the surface reads as rising out of the rail rather than blinking on. Only
/// the first appearance animates: the state is rebuilt for every position tick
/// and must not replay this while the user is listening.
class _PillArrival extends StatelessWidget {
  const _PillArrival({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SpringValue(
      value: 1,
      animateOnMount: true,
      spring: FathomMotion.gentle,
      builder: (context, t) {
        final eased = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - eased)),
            child: Transform.scale(
              scale: 0.97 + 0.03 * eased,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The elapsed-time tint: a translucent rect behind the pill face whose width
/// is the playback progress. It rides inside the glass clip, so the pill's
/// own radius rounds it.
class _PillProgress extends StatelessWidget {
  const _PillProgress({required this.player});

  final FathomPlayer player;

  @override
  Widget build(BuildContext context) {
    // Duration lands late (after the stream resolves), so it must be read on
    // every position tick, not when the pill first builds — otherwise the tint
    // never appears on a freshly started track.
    return StreamBuilder<Duration>(
      stream: player.audioPlayer.positionStream,
      builder: (context, snapshot) {
        final total = player.duration?.inMilliseconds ?? 0;
        if (total <= 0) return const SizedBox.shrink();

        final elapsed = (snapshot.data ?? Duration.zero).inMilliseconds;
        // Align + FractionallySizedBox leaves the child loose constraints,
        // and a childless ColoredBox collapses to zero size under loose
        // constraints — the rect never painted. SizedBox.expand pins it to
        // the fractional box instead.
        return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (elapsed / total).clamp(0.0, 1.0),
          child: SizedBox.expand(
            child: ColoredBox(color: FathomColors.fill),
          ),
        );
      },
    );
  }
}

/// The pill's track face, driven by the same slot deck as the cover carousel:
/// art and title move as one card, the neighbours slide in from the edges
/// under the same spring, and a committed swipe swaps the track rather than
/// animating a page index.
class _PillCards extends StatefulWidget {
  const _PillCards({
    required this.track,
    required this.previous,
    required this.next,
    required this.library,
    required this.onOpen,
    required this.onSkipNext,
    required this.onSkipPrevious,
  });

  final FathomTrack track;
  final FathomTrack? previous;
  final FathomTrack? next;
  final FathomLibrary library;
  final VoidCallback onOpen;
  final Future<void> Function() onSkipNext;
  final Future<void> Function() onSkipPrevious;

  @override
  State<_PillCards> createState() => _PillCardsState();
}

class _PillCardsState extends State<_PillCards>
    with SingleTickerProviderStateMixin {
  static const _spring = FathomMotion.momentum;
  static const _edgeResistance = 0.3;
  static const _neighbourScale = 0.14;
  static const _neighbourFade = 0.5;
  static const _gap = 12.0;

  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this);

  double _spacing = 1;

  @override
  void didUpdateWidget(_PillCards old) {
    super.didUpdateWidget(old);
    if (old.track.id == widget.track.id) return;

    // The skip changed the track underneath us: shift the deck by one slot so
    // the new card lands exactly where the old one was, then spring home.
    var dir = 0;
    if (old.next?.id == widget.track.id) {
      dir = 1;
    } else if (old.previous?.id == widget.track.id) {
      dir = -1;
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
    final startId = widget.track.id;
    try {
      await (dir > 0 ? widget.onSkipNext() : widget.onSkipPrevious());
    } catch (_) {}
    await SchedulerBinding.instance.endOfFrame;
    // If the skip never landed (previous restarting a track past 3s, or a
    // blocked edge), spring the deck home from here.
    if (!mounted || widget.track.id != startId) return;
    _springTo(0, _offset.velocity);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cardWidth = c.maxWidth;
        _spacing = cardWidth + _gap;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          onHorizontalDragCancel: _onCancel,
          child: ClipRect(
            child: SizedBox(
              width: cardWidth,
              height: 40,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (widget.previous != null)
                    _pillCard(-1, widget.previous!, cardWidth),
                  _pillCard(0, widget.track, cardWidth),
                  if (widget.next != null)
                    _pillCard(1, widget.next!, cardWidth),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pillCard(int slot, FathomTrack track, double cardWidth) {
    return _PillCard(
      slot: slot,
      offset: _offset,
      spacing: _spacing,
      neighbourScale: _neighbourScale,
      neighbourFade: _neighbourFade,
      child: RepaintBoundary(
        child: _PillCardFace(
          track: track,
          width: cardWidth,
          library: widget.library,
          // Only the card on screen is the source of the flight. The
          // neighbours are a peek at what a swipe would reach, and tagging
          // them would create two heroes for one tag.
          hero: slot == 0,
        ),
      ),
    );
  }
}

class _PillCard extends StatelessWidget {
  const _PillCard({
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

/// One card face: art plus the title/artist pair, so all three slide together.
class _PillCardFace extends StatelessWidget {
  const _PillCardFace({
    required this.track,
    required this.width,
    required this.library,
    required this.hero,
  });

  final FathomTrack track;
  final double width;
  final FathomLibrary library;

  /// Whether this card carries the shared-element tags Now Playing receives.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    Widget art = TrackArt(
      library: library,
      track: track,
      size: 40,
      radius: 50,
    );
    if (hero) {
      art = Hero(tag: 'fathom-art-${track.id}', child: art);
    }

    Widget text = TrackTextMorph(
      title: track.title,
      artist: track.artist,
      titleStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: -0.14,
        color: FathomColors.onSurface,
      ),
      artistStyle: TextStyle(
        fontSize: 11,
        color: FathomColors.onSurface.withValues(alpha: 0.5),
      ),
      gap: 1,
    );
    if (hero) {
      text = Hero(
        tag: 'fathom-text-${track.id}',
        flightShuttleBuilder: trackTextHeroShuttle,
        child: text,
      );
    }

    return SizedBox(
      width: width,
      child: Row(
        children: [
          art,
          const SizedBox(width: 12),
          Expanded(child: text),
        ],
      ),
    );
  }
}
