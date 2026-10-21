import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'common/library.dart';
import 'common/player.dart';
import 'common/settings.dart';
import 'components/art.dart';
import 'components/backdrop.dart';
import 'components/flat_icon_button.dart';
import 'components/page_header.dart';
import 'components/shell_chrome.dart';
import 'components/toast_layer.dart';
import 'models/tracks.dart';
import 'pages/equalizer.dart';
import 'pages/library.dart';
import 'panels/bottom_panel.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

/// The ambient backdrop behind the shell, carrying the current track's artwork
/// so the gradient follows whatever is playing.
///
/// It reads the player and the library itself, which keeps the shared chrome
/// ignorant of both and lets the shell hand out a constant instance: the
/// artwork future only re-resolves when the current track changes.
class _TrackBackdrop extends StatelessWidget {
  const _TrackBackdrop();

  @override
  Widget build(BuildContext context) {
    final track = context.select<FathomPlayer, FathomTrack?>(
      (player) => player.currentTrack,
    );
    final library = context.read<FathomLibrary>();

    return AmbientBackdrop(
      artwork: track == null ? null : trackArtBytes(library, track),
    );
  }
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

  /// Whether the page stack is mid-transition, so a tap on the other nav item
  /// is dropped instead of queueing a second scroll behind the first.
  bool _animating = false;

  /// Mirrors whether the search rail is expanded. The dismiss layer needs it
  /// in the shell, where it can cover the page as well as the rail.
  final ValueNotifier<bool> _searchOpen = ValueNotifier<bool>(false);

  /// Coordinates the now-playing hero between the mini player and the page
  /// below it: written by both, read by both, so the shell owns it.
  final ValueNotifier<bool> heroFromPanel = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // A swipe is the other way to change pages, so the view has to write back
    // into the same notifier the rail reads. Done here rather than in a
    // listener on the controller because `PageView` only reports a settled
    // page, which is exactly when the destination has really changed.
    _pages.addListener(_onPageSettled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = context.read<FathomLibrary>();
      context.read<FathomPlayer>().attachLibrary(library);
    });
  }

  @override
  void dispose() {
    _pages.removeListener(_onPageSettled);
    _pages.dispose();
    _searchController.dispose();
    _page.dispose();
    _searchOpen.dispose();
    heroFromPanel.dispose();
    super.dispose();
  }

  /// Adopts a swipe as the new destination once the view has come to rest.
  ///
  /// Half-way is the threshold: `page.round()` is the nearest page, so a swipe
  /// that was dragged back to its origin leaves the destination alone.
  ///
  /// Leaving the library drops any search, exactly as a rail tap does, so a
  /// swipe away cannot strand the open search field and its dismiss layer on a
  /// page that no longer shows them.
  void _onPageSettled() {
    if (_pages.page == null) return;
    final settled = ShellPage.values[_pages.page!.round()];
    if (settled == _page.value) return;
    FocusScope.of(context).unfocus();
    _page.value = settled;
  }

  /// Moves to another destination. A rail tap is the same move a swipe makes,
  /// so it scrolls the view rather than swapping anything, and the swipe back
  /// is symmetric for free.
  ///
  /// The notifier is only written through [_runTransition], so a tap dropped
  /// while a move is already in flight cannot leave the rail highlighting one
  /// destination while the view sits on another.
  void _goTo(ShellPage target) {
    if (_page.value == target) return;
    FocusScope.of(context).unfocus();
    _runTransition(target);
  }

  /// Scrolls the view to [target] and locks nav taps until it settles, so a
  /// second tap cannot queue a scroll behind an in-flight one.
  void _runTransition(ShellPage target) {
    if (_animating) return;
    _animating = true;
    setState(() {});
    _page.value = target;
    _pages
        .animateToPage(
      target.index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    )
        .whenComplete(() {
      if (!mounted) return;
      setState(() => _animating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop plus header, built once. Only the page body below it
          // animates when the destination changes, so neither layer is
          // duplicated or cross-faded with the outgoing page.
          ValueListenableBuilder<ShellPage>(
            valueListenable: _page,
            builder: (context, page, _) => ShellChrome(
              backdrop: const _TrackBackdrop(),
              header: PageHeader(
                title: page.title,
                trailing: page == ShellPage.library
                    ? shellTrailing(context)
                    : _equalizerTrailing(context),
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
                // A page is wide enough to read one at a time; the swipe is a
                // deliberate move between two destinations, not a carousel.
                physics: const PageScrollPhysics(),
                children: [
                  _KeepAlive(
                    child: RepaintBoundary(
                      child: LibraryPage(heroFromPanel: heroFromPanel),
                    ),
                  ),
                  const _KeepAlive(
                    child: RepaintBoundary(child: EqualizerPage()),
                  ),
                ],
              ),
            ),
          ),
          // Messages live directly under the header and above every page, so a
          // download report never lands on the mini player or the rail that it
          // is usually about. The layer decides its own pointer behaviour: a
          // toast is information and must not take a tap meant for the list,
          // but a long-running card carries a close control that has to be
          // reachable, so the decision cannot be made here.
          const Positioned.fill(child: FathomToastLayer()),
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
              animating: _animating,
              onGoTo: _goTo,
              onSearchOpenChanged: (open) => _searchOpen.value = open,
              searchController: _searchController,
              heroFromPanel: heroFromPanel,
            ),
          ),
        ],
      ),
    );
  }

  /// Trailing controls for the Equalizer destination.
  ///
  /// The reset clears the curve. Leaving the equalizer is the rail's job now,
  /// so there is deliberately no back button here: the nav item is the one way
  /// between destinations.
  List<Widget> _equalizerTrailing(BuildContext context) => [
        FlatIconButton(
          icon: TablerIcons.refresh,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: context.read<FathomSettings>().accent,
          onTap: () => context.read<FathomPlayer>().applyEqPreset('Flat'),
        ),
      ];
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
