import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'common/library.dart';
import 'common/motion.dart';
import 'common/player.dart';
import 'common/selection.dart';
import 'common/settings.dart';
import 'components/backdrop.dart';
import 'components/flat_icon_button.dart';
import 'components/limiter_button.dart';
import 'components/page_header.dart';
import 'components/shell_chrome.dart';
import 'pages/equalizer.dart';
import 'pages/library.dart';
import 'panels/bottom_panel.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

/// The shell's two destinations, in rail order.
///
/// The title each page wears lives here rather than on the page, because the
/// shell owns the header now: it renders the row once, outside the cross-fade,
/// and only the body below it changes when a destination does.
enum ShellPage {
  library('Library'),
  equalizer('Equalizer');

  const ShellPage(this.title);

  /// The header title for this destination.
  final String title;
}

class _RootShellState extends State<RootShell> {
  final TextEditingController _searchController = TextEditingController();

  /// The destination currently on screen. The rail highlights from it and the
  /// swipe view scrolls to it.
  final ValueNotifier<ShellPage> _page =
      ValueNotifier<ShellPage>(ShellPage.library);

  /// Drives the horizontal page swipe, and is what a rail tap animates.
  /// `ShellPage.values` order is the page order, so `index` is the page.
  late final PageController _pages = PageController(
    initialPage: _page.value.index,
  );

  /// How long a rail tap takes to slide the body to the other destination.
  ///
  /// Short on purpose: the destination changes on the tap itself, so the slide
  /// only has to carry the eye across. Anything longer reads as waiting for
  /// the app rather than as a transition. [FathomSpringCurve] gives the move
  /// the same decelerating arrival as the springs elsewhere; the page view's
  /// own drag settle stays on its built-in spring.
  static const Duration _pageTransitionDuration = Duration(milliseconds: 200);

  /// Mirrors whether the search rail is expanded. The dismiss layer needs it
  /// in the shell, where it can cover the page as well as the rail.
  final ValueNotifier<bool> _searchOpen = ValueNotifier<bool>(false);

  /// The library's multi-track selection.
  ///
  /// It lives on the shell rather than the page because the header is built
  /// outside the page body: the title and the select-all control have to read
  /// the same selection the rows do. Nothing persists it — leaving the library
  /// drops it, and so does typing in the search field.
  final FathomSelection _selection = FathomSelection();

  @override
  void initState() {
    super.initState();
    _page.addListener(_onPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = context.read<FathomLibrary>();
      context.read<FathomPlayer>().attachLibrary(library);
    });
  }

  @override
  void dispose() {
    _page.removeListener(_onPageChanged);
    _selection.dispose();
    _pages.dispose();
    _searchController.dispose();
    _page.dispose();
    _searchOpen.dispose();
    super.dispose();
  }

  /// Drops the selection when the library stops being the destination.
  ///
  /// The subscription is to the page notifier itself, so a rail tap and a
  /// settled swipe are both covered: both paths write `_page`, and the header
  /// and rows are describing a surface that is no longer on screen.
  void _onPageChanged() {
    if (_page.value != ShellPage.library) _selection.exit();
  }

  /// Moves to another destination from the rail.
  ///
  /// The destination is written before the scroll starts and the scroll is not
  /// awaited: the rail and the header answer the tap in the same frame while
  /// the body catches up. A second tap retargets the animation in flight rather
  /// than being dropped. Nothing else can change the destination: the page view
  /// has no drag physics, so a stray horizontal gesture never leaves the page
  /// the rail chose.
  void _goTo(ShellPage target) {
    if (_page.value == target) return;
    FocusScope.of(context).unfocus();
    if (target == ShellPage.equalizer) {
      // Arriving at the equalizer is the moment its dials have to work. The
      // health check rebuilds a native effect the platform has released.
      unawaited(context.read<FathomPlayer>().ensureEqReady());
    }
    _page.value = target;
    _pages.animateToPage(
      target.index,
      duration: _pageTransitionDuration,
      curve: const FathomSpringCurve(),
    );
  }

  /// The header title for [page].
  ///
  /// Selecting replaces the destination's title with the size of the selection,
  /// which is the one thing the mode has to communicate while the rows
  /// themselves are being tapped. Zero selected is named rather than counted so
  /// entering the mode never reads as "0 selected".
  String _headerTitle(ShellPage page) {
    if (page != ShellPage.library || !_selection.active) return page.title;
    final count = _selection.count;
    return count == 0 ? 'Select tracks' : '$count selected';
  }

  @override
  Widget build(BuildContext context) {
    return _SelectionPopScope(
      selection: _selection,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop plus header, built once. Only the page body below it
            // animates when the destination changes, so neither layer is
            // duplicated or cross-faded with the outgoing page.
            ValueListenableBuilder<ShellPage>(
              valueListenable: _page,
              builder: (context, page, _) => ShellChrome(
                backdrop: const AmbientBackdrop(),
                // Only the header listens to the selection. The page body below
                // must not be rebuilt by the shell when a row is toggled: the
                // library repaints its own rows, and keeping the two layers
                // independent is what preserves the mounted list.
                header: ListenableBuilder(
                  listenable: _selection,
                  builder: (context, _) => PageHeader(
                    title: _headerTitle(page),
                    trailing: page == ShellPage.library
                        ? shellTrailing(context, selection: _selection)
                        : _equalizerTrailing(context),
                  ),
                ),
                // The swipe view owns the body only: the title and its controls
                // change in place while the bodies slide past each other, which
                // is what keeps the header from moving with them.
                //
                // Both destinations stay mounted. The library is the expensive
                // one — it owns a scroll controller, the sorted/filtered list
                // memos and the live remote search — so it is never disposed, and
                // swiping away only moves it off screen. An `AnimatedSwitcher`
                // would destroy it on every trip to the equalizer and rebuild it
                // (and re-run the library scan) on the way back.
                body: PageView(
                  controller: _pages,
                  // Destinations change only from the rail. The view is kept so
                  // a rail tap can still animate the body across, but a
                  // horizontal drag must not leave a page the rail did not pick.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _KeepAlive(
                      child: RepaintBoundary(
                        child: LibraryPage(selection: _selection),
                      ),
                    ),
                    const _KeepAlive(
                      child: RepaintBoundary(child: EqualizerPage()),
                    ),
                  ],
                ),
              ),
            ),
            // Full-screen dismiss layer for the search rail. It sits between
            // the page and the panel: the panel paints and hit-tests above it,
            // so the rail, the mini player and the field's own context menu are
            // never swallowed by it. Only presses on the page reach it, which is
            // exactly where a stray tap could start playback.
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _searchOpen,
                builder: (context, searching, _) => !searching
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => FocusScope.of(context).unfocus(),
                      ),
              ),
            ),
            Positioned.fill(
              child: BottomPanel(
                page: _page,
                onGoTo: _goTo,
                onSearchOpenChanged: (open) => _searchOpen.value = open,
                searchController: _searchController,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trailing controls for the Equalizer destination.
  ///
  /// The reset clears the curve. Leaving the equalizer is the rail's job now,
  /// so there is deliberately no back button here: the nav item is the one way
  /// between destinations.
  List<Widget> _equalizerTrailing(BuildContext context) => [
        const LimiterButton(),
        FlatIconButton(
          icon: TablerIcons.refresh,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: context.read<FathomSettings>().accent,
          onTap: () => context.read<FathomPlayer>().applyEqPreset('Flat'),
        ),
      ];
}

/// Intercepts the system back gesture while a library selection is active.
///
/// Selection is a mode, not a route, so the first back press must leave the
/// mode rather than the app. A [PopScope] keeps that rule in the shell, where
/// the selection lives, and stays out of the page body's build.
class _SelectionPopScope extends StatelessWidget {
  const _SelectionPopScope({required this.selection, required this.child});

  final FathomSelection selection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selection.active) selection.exit();
      },
      child: child,
    );
  }
}

/// Keeps a swipe view page mounted while it is off screen.
///
/// `PageView` builds a page when it scrolls into view and — with the default
/// settings — can let it go once it is far enough away. That would undo the
/// whole point of keeping the library alive: leaving for the equalizer would
/// drop its scroll position, its memoised lists and its running search, and
/// coming back would rescan. `AutomaticKeepAliveClientMixin` is the mechanism
/// `PageView` gives for opting out of that, and this is the smallest widget
/// that can use it.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // Required by the mixin, which records the keep-alive request here.
    super.build(context);
    return widget.child;
  }
}
