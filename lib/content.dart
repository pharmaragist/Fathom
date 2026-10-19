import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'common/library.dart';
import 'common/player.dart';
import 'components/backdrop.dart';
import 'pages/equalizer.dart';
import 'pages/library.dart';
import 'panels/bottom_panel.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final Set<int> _visitedPages = {0};
  final TextEditingController _searchController = TextEditingController();

  /// Mirrors whether the search rail is expanded. The dismiss layer needs it
  /// in the shell, where it can cover the pages as well as the rail.
  final ValueNotifier<bool> _searchOpen = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = context.read<FathomLibrary>();
      context.read<FathomPlayer>().attachLibrary(library);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BackdropWrapper(),
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: [
                _visitedPages.contains(0)
                    ? const RepaintBoundary(child: LibraryPage())
                    : const SizedBox.shrink(),
                _visitedPages.contains(1)
                    ? const RepaintBoundary(child: EqualizerPage())
                    : const SizedBox.shrink(),
              ],
            ),
          ),
          Positioned.fill(
            child: BottomPanel(
              currentIndex: _index,
              onNavChanged: (i) {
                setState(() {
                  _index = i;
                  _visitedPages.add(i);
                });
              },
              searchController: _searchController,
              searchOpen: _searchOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropWrapper extends StatelessWidget {
  const _BackdropWrapper();

  @override
  Widget build(BuildContext context) {
    final trackId = context.select<FathomPlayer, int?>(
      (player) => player.currentTrack?.id,
    );
    final library = context.read<FathomLibrary>();

    return AmbientBackdrop(
      trackId: trackId,
      artwork: trackId == null ? null : library.artFor(trackId),
    );
  }
}
