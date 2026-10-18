import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/constants.dart';
import '../common/states.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/art.dart';
import '../components/glass.dart';
import '../components/nav_rail.dart';
import '../models/tracks.dart';
import '../pages/library.dart' show chooseSortBottomSheet, LibrarySort;
import '../pages/playing.dart' show NowPlayingPage;

class BottomPanel extends StatelessWidget {
  const BottomPanel({
    super.key,
    required this.currentIndex,
    required this.onNavChanged,
    required this.searchController,
  });

  final int currentIndex;
  final ValueChanged<int> onNavChanged;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final sortIndex = context.select<FathomSettings, int>(
      (s) => s.get<int>(SettingKey.sortIndex),
    );
    final currentSort = LibrarySort.values[
      sortIndex.clamp(0, LibrarySort.values.length - 1)
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Consumer<FathomSettings>(
            builder: (context, settings, _) => FloatingNavRail(
              index: currentIndex,
              accent: settings.accent,
              bottomSafe: bottomSafe,
              onChanged: onNavChanged,
              searchController: searchController,
              onSearchChanged: (q) => searchQuery.value = q,
              onSearchCleared: () {
                searchController.clear();
                searchQuery.value = '';
              },
              sortLabel: currentSort.label,
              onSort: () => chooseSortBottomSheet(
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
          child: const FloatingIslandPlayer(),
        ),
      ],
    );
  }
}

class FloatingIslandPlayer extends StatefulWidget {
  const FloatingIslandPlayer({super.key});

  @override
  State<FloatingIslandPlayer> createState() => _FloatingIslandPlayerState();
}

class _FloatingIslandPlayerState extends State<FloatingIslandPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragOffset = 0.0;
  static const double _swipeThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final player = context.read<FathomPlayer>();
    final velocity = details.primaryVelocity ?? 0.0;

    if (_dragOffset.abs() > _swipeThreshold || velocity.abs() > 400) {
      if (_dragOffset < 0 && player.canSkipNext) {
        player.skipNext();
      } else if (_dragOffset > 0 && player.canSkipPrevious) {
        player.skipPrevious();
      }
    }

    _resetDrag();
  }

  void _resetDrag() {
    _controller.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = 0.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrent = context.select<FathomPlayer, bool>(
      (player) => player.hasCurrent,
    );
    if (!hasCurrent) return const SizedBox.shrink();

    final track = context.select<FathomPlayer, FathomTrack?>(
      (player) => player.currentTrack,
    );
    final isPlaying = context.select<FathomPlayer, bool>(
      (player) => player.isPlaying,
    );
    final library = context.read<FathomLibrary>();
    if (track == null) return const SizedBox.shrink();

    return GlassContainer(
      radius: kPillHeight / 2,
      bgOpacity: 0.11,
      borderOpacity: 0.07,
      shadow: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onHorizontalDragCancel: _resetDrag,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openNowPlaying(context),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final resetProgress = _controller.isAnimating
                        ? CurvedAnimation(
                            parent: _controller,
                            curve: Curves.easeOutBack,
                          ).value
                        : 0.0;

                    final currentOffset = _controller.isAnimating
                        ? _dragOffset * (1.0 - resetProgress)
                        : _dragOffset;

                    final progress = (currentOffset / 160.0).clamp(-1.0, 1.0);
                    final opacity = (1.0 - (progress.abs() * 0.7)).clamp(0.0, 1.0);
                    final scale = 1.0 - (progress.abs() * 0.08);

                    return Transform.translate(
                      offset: Offset(currentOffset, 0),
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: heroFromPanel,
                        builder: (context, fromPanel, child) =>
                            HeroMode(enabled: fromPanel, child: child!),
                        child: Hero(
                          tag: 'fathom-art-${track.id}',
                          child: ArtThumb(
                            id: track.id,
                            artwork: library.artFor(track.id),
                            size: 36,
                            radius: 50,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: -0.14,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
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
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                context.read<FathomPlayer>().togglePlay();
              },
              icon: Icon(
                isPlaying
                    ? TablerIcons.playerPauseFilled
                    : TablerIcons.playerPlayFilled,
                size: 24,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNowPlaying(BuildContext context) {
    heroFromPanel.value = true;
    Navigator.of(context).push(_nowPlayingRoute());
  }
}

Route<void> _nowPlayingRoute() {
  return PageRouteBuilder<void>(
    fullscreenDialog: true,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (context, animation, secondaryAnimation) =>
        const NowPlayingPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
