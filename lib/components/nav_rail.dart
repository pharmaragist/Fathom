import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/motion.dart';
import '../content.dart' show ShellPage;
import 'glass.dart';

const double kPillHeight = 64;
const double kHorizontalMargin = 4;
const double kElevationMargin = 6;
const double kNavBarHeight = 64;

/// Horizontal inset of the drawn pill inside one nav item's slot. The slot is
/// wider than the two items need, so the highlight reads as a pill behind the
/// item rather than a band touching its neighbours.
const double kPillInset = 6;

class FloatingNavRail extends StatefulWidget {
  const FloatingNavRail({
    super.key,
    required this.accent,
    required this.bottomSafe,
    required this.searchController,
    required this.query,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSearchOpenChanged,
    required this.page,
    required this.onGoTo,
    this.sortLabel,
    this.onSort,
    this.hintText = 'Search library and YouTube',
  });

  final Color accent;
  final double bottomSafe;
  final TextEditingController searchController;

  /// The applied filter, the same value the library list is driven by. It stays
  /// set after the rail collapses, which is what the dismiss icon reports.
  final ValueListenable<String> query;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;

  /// Reports the expanded state so the shell can put a dismiss layer over the
  /// pages for as long as the query field is on screen.
  final ValueChanged<bool> onSearchOpenChanged;

  /// The destination on screen, which is what marks its nav item active.
  final ValueListenable<ShellPage> page;

  /// Moves the shell to another destination.
  final ValueChanged<ShellPage> onGoTo;

  /// Sorting is a Library concern; absent when the active page has no order.
  final String? sortLabel;
  final VoidCallback? onSort;

  /// Names the source the field is editing, so it never lies about what a
  /// keystroke filters.
  final String hintText;

  @override
  State<FloatingNavRail> createState() => _FloatingNavRailState();
}

class _FloatingNavRailState extends State<FloatingNavRail> {
  static const _debounceDuration = Duration(milliseconds: 300);

  bool _isSearching = false;
  Timer? _debounce;
  final FocusNode _searchFocus = FocusNode();

  /// The rail carries the two destinations plus the search button, which is
  /// what it actually does beyond navigation.

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    super.dispose();
  }

  /// Collapses the search rail as soon as the query field loses focus, so the
  /// bar does not linger after tapping outside it, submitting, or dismissing the
  /// keyboard.
  void _onSearchFocusChanged() {
    if (!_searchFocus.hasFocus && _isSearching) _toggleSearch(false);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      widget.onSearchChanged(value);
      return;
    }
    _debounce = Timer(_debounceDuration, () => widget.onSearchChanged(value));
  }

  void _onQuerySubmitted(String value) {
    _debounce?.cancel();
    widget.onSearchChanged(value);
  }

  void _toggleSearch(bool active) {
    _debounce?.cancel();
    if (active) {
      // Collapsing flushes the field into the applied query, so an empty query
      // here can only be a stale draft left behind by an external clear.
      if (widget.query.value.isEmpty) widget.searchController.clear();
      setState(() => _isSearching = true);
      widget.onSearchOpenChanged(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
      return;
    }

    // Flush the keystroke still sitting in the debounce so the held query
    // matches what the field shows once it collapses.
    widget.onSearchChanged(widget.searchController.text);

    setState(() => _isSearching = false);
    widget.onSearchOpenChanged(false);
    // Drop focus after clearing the flag so the focus listener does not
    // re-enter this branch. The layer stays up while the field is focused, so
    // a page tap only collapses the keyboard first; the layer takes the second
    // tap.
    _searchFocus.unfocus();
  }

  /// Reopens the field with the held query, caret at the end, so a search can
  /// be refined instead of cleared and retyped.
  void _editQuery() {
    final text = widget.query.value;
    widget.searchController.text = text;
    widget.searchController.selection = TextSelection.collapsed(
      offset: text.length,
    );
    _toggleSearch(true);
  }

  Widget _switcherLayout(Widget? current, List<Widget> previous) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [...previous, if (current != null) current],
    );
  }

  @override
  Widget build(BuildContext context) {
    final notchDepth = kPillHeight / 2 + kElevationMargin;

    return SizedBox(
      width: double.infinity,
      height: notchDepth + kNavBarHeight + widget.bottomSafe,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _NotchedNavClipper(),
              child: _RailGlass(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        FathomColors.onSurface.withValues(alpha: 0.14),
                        FathomColors.onSurface.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: notchDepth,
            height: kNavBarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  const searchBtnWidth = 48.0;

                  return ValueListenableBuilder<String>(
                    valueListenable: widget.query,
                    builder: (context, query, _) {
                      // A held query widens the leading slot into the
                      // edit-and-clear pair.
                      final hasQuery = query.isNotEmpty;
                      final leadingWidth =
                          hasQuery ? searchBtnWidth * 2 : searchBtnWidth;
                      // The nav area starts after the search control. The
                      // background collapses back into it; the navLeft and
                      // navWidth it needs are the same split, since the rail's
                      // left edge is this box's zero.
                      final navLeft = leadingWidth;
                      final navWidth = totalWidth - leadingWidth;

                      return Stack(
                        children: [
                          // The one background, under everything, so its geometry
                          // never depends on which mode is on screen. It has two
                          // homes: behind the active nav item, and the whole
                          // rail once the field expands.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _NavBackground(
                                accent: widget.accent,
                                page: widget.page,
                                expanded: _isSearching,
                                totalWidth: totalWidth,
                                navLeft: navLeft,
                                navWidth: navWidth,
                              ),
                            ),
                          ),
                          // The pill sits above the background while idle, which
                          // is what keeps the active icon and label readable on
                          // the accent fill rather than under it. In search mode
                          // the field is the only content on this box, so it
                          // reaches the background because nothing overlaps it.
                          if (!_isSearching)
                            Positioned(
                              left: navLeft,
                              width: navWidth,
                              top: 0,
                              bottom: 0,
                              child: _NavItems(
                                page: widget.page,
                                onGoTo: widget.onGoTo,
                              ),
                            ),
                          Positioned.fill(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              layoutBuilder: _switcherLayout,
                              transitionBuilder: (child, animation) {
                                // The field replaces the nav items in place, so
                                // a spring settle plus a small scale keeps the
                                // two states feeling like one surface changing
                                // role instead of two screens cross-fading.
                                final curved = CurvedAnimation(
                                  parent: animation,
                                  curve: const FathomSpringCurve(),
                                  reverseCurve: Curves.easeInCubic,
                                );
                                return FadeTransition(
                                  opacity: curved,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.97,
                                      end: 1.0,
                                    ).animate(curved),
                                    child: child,
                                  ),
                                );
                              },
                              child: _isSearching
                                  ? _NavSearchContent(
                                      key: const ValueKey('search_mode'),
                                      controller: widget.searchController,
                                      accent: widget.accent,
                                      sortLabel: widget.sortLabel,
                                      onSort: widget.onSort,
                                      hintText: widget.hintText,
                                      onChanged: _onQueryChanged,
                                      onSubmitted: _onQuerySubmitted,
                                      onClose: () => _toggleSearch(false),
                                      focusNode: _searchFocus,
                                    )
                                  : Row(
                                      key: const ValueKey('nav_mode'),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (hasQuery) ...[
                                          // A held query shows how to edit it
                                          // beside the button that drops it.
                                          SizedBox(
                                            width: searchBtnWidth,
                                            child: IconButton(
                                              icon: const Icon(
                                                  TablerIcons.pencil,
                                                  size: 18),
                                              color: FathomColors.onSurface
                                                  .withValues(alpha: 0.9),
                                              onPressed: _editQuery,
                                            ),
                                          ),
                                          SizedBox(
                                            width: searchBtnWidth,
                                            child: IconButton(
                                              icon: const Icon(TablerIcons.x,
                                                  size: 20),
                                              color: FathomColors.onSurface
                                                  .withValues(alpha: 0.9),
                                              onPressed: widget.onSearchCleared,
                                            ),
                                          ),
                                        ] else
                                          SizedBox(
                                            width: searchBtnWidth,
                                            child: IconButton(
                                              icon: const Icon(
                                                  TablerIcons.search,
                                                  size: 20),
                                              color: FathomColors.onSurface
                                                  .withValues(alpha: 0.72),
                                              onPressed: () =>
                                                  _toggleSearch(true),
                                            ),
                                          ),
                                        // The background layer already drew
                                        // this area's pill, so the nav content
                                        // only has to fill the same box.
                                        Expanded(
                                          child: _NavItems(
                                            page: widget.page,
                                            onGoTo: widget.onGoTo,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavSearchContent extends StatelessWidget {
  const _NavSearchContent({
    super.key,
    required this.controller,
    required this.accent,
    this.sortLabel,
    this.onSort,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
    required this.focusNode,
  });

  final TextEditingController controller;
  final Color accent;

  /// Sorting is a Library concern; absent when the active page has no order.
  final String? sortLabel;
  final VoidCallback? onSort;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClose;
  final FocusNode focusNode;

  void _handleTrailing() {
    if (controller.text.isEmpty) {
      onClose();
      return;
    }
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    // One tap region for the whole search bar. The field's own
    // `onTapOutside` used to fire for the sort chip too, which unfocused the
    // field and collapsed the bar before the chip could handle its tap. A
    // group around the field, chip and close control keeps every control in
    // here alive; only a press outside the bar dismisses it.
    return TapRegion(
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(TablerIcons.search, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: (value) {
                  onSubmitted(value);
                  FocusScope.of(context).unfocus();
                },
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  color: FathomColors.onSurface,
                ),
                cursorColor: accent,
                cursorHeight: 18,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: hintText,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    color: FathomColors.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (sortLabel != null)
              _SortChip(
                label: sortLabel!,
                accent: accent,
                onTap: () {
                  // Sorting is a library action, not typing. Drop the
                  // keyboard first so the sheet is not squeezed above it, but
                  // do it from the chip's own tap: the field's old
                  // onTapOutside fired on pointer-down and removed the chip
                  // before it could handle the tap.
                  FocusScope.of(context).unfocus();
                  onSort!();
                },
              ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return _RoundIconButton(
                  icon: value.text.isEmpty
                      ? TablerIcons.x
                      : TablerIcons.backspace,
                  color: FathomColors.onSurface.withValues(alpha: 0.6),
                  onTap: _handleTrailing,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.16),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(TablerIcons.arrowsSort, size: 14, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: FathomColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(child: Icon(icon, size: 18, color: color)),
        ),
      ),
    );
  }
}

/// The rail's frosted layer.
///
/// This is the largest blurred surface in the app, and it sits directly over
/// the shell's page swipe: the page content moves under the rail on every
/// frame of that gesture, so the [BackdropFilter] has a different backdrop
/// each frame and cannot reuse its result. Profiling the swipe put that cost
/// on the raster thread — ~12-25ms a frame against an 11ms budget on a 90Hz
/// panel — while the UI thread stayed under 1ms, which is why the gesture
/// feels heavy without any Dart work to show for it.
///
/// Reading [GlassContainer.blurEnabled] is what makes Low-end mode mean
/// something here: that setting exists to drop exactly this kind of cost, and
/// the rail was the one glass surface that ignored it. Flat, the rail keeps
/// its gradient and still reads as a raised bar; only the frosting goes.
class _RailGlass extends StatelessWidget {
  const _RailGlass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!GlassContainer.blurEnabled) return child;
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: child,
    );
  }
}

class _NotchedNavClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    final r = kPillHeight / 2;
    final m = kElevationMargin;
    final d = r + m;
    final pillLeft = kHorizontalMargin;
    final pillRight = w - kHorizontalMargin;

    return Path()
      ..moveTo(0, 0)
      ..lineTo(pillLeft - m, 0)
      ..arcToPoint(
        Offset(pillLeft + r, d),
        radius: Radius.circular(r + m),
        clockwise: false,
      )
      ..lineTo(pillRight - r, d)
      ..arcToPoint(
        Offset(pillRight + m, 0),
        radius: Radius.circular(r + m),
        clockwise: false,
      )
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(covariant _NotchedNavClipper oldClipper) => false;
}

/// The two nav destinations in rail order.
///
/// The two items always fill the nav area, so the background that sits behind
/// them is a separate layer ([_NavBackground]) rather than a second pass of this
/// layout. Nothing here needs to know that background exists.
class _NavItems extends StatelessWidget {
  const _NavItems({required this.page, required this.onGoTo});

  final ValueListenable<ShellPage> page;
  final ValueChanged<ShellPage> onGoTo;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShellPage>(
      valueListenable: page,
      builder: (context, current, _) {
        final library = _NavItem(
          icon: TablerIcons.discFilled,
          label: 'Library',
          active: current == ShellPage.library,
          onTap: () => onGoTo(ShellPage.library),
        );
        final equalizer = _NavItem(
          icon: TablerIcons.waveSine,
          label: 'Equalizer',
          active: current == ShellPage.equalizer,
          onTap: () => onGoTo(ShellPage.equalizer),
        );

        // Half the nav area per destination, in rail order. The two items share
        // the width evenly, and the background reads the same split off its own
        // box, which is the nav area too.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: library),
            Expanded(child: equalizer),
          ],
        );
      },
    );
  }
}

/// The single background of the rail, in both of its states.
///
/// It exists to make the search field look like it *comes from* the active nav
/// item: idle, it is a rounded accent pill behind Library or Equalizer; expanded,
/// it stretches left to the rail's leading edge and out to the full width, i.e.
/// the toolbar background. Animating the same element between those two boxes is
/// what reads as the pill growing into the field; two separate elements could
/// only cross-fade, which would lose the connection.
///
/// The geometry is resolved against the full rail width rather than the nav area
/// alone, because the expanded state has to reach past the nav area's left edge.
class _NavBackground extends StatelessWidget {
  const _NavBackground({
    required this.accent,
    required this.page,
    required this.expanded,
    required this.totalWidth,
    required this.navLeft,
    required this.navWidth,
  });

  final Color accent;
  final ValueListenable<ShellPage> page;

  /// True while the search field is on screen, i.e. while this is the toolbar's
  /// background instead of one item's highlight.
  final bool expanded;

  final double totalWidth;

  /// The nav area's left edge, which is where the idle geometry starts counting.
  final double navLeft;
  final double navWidth;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShellPage>(
      valueListenable: page,
      builder: (context, current, _) {
        // The item's slot as this layer measures it: the nav area split in two,
        // in rail order. Which slot is active tracks the page, so switching
        // destinations slides the pill rather than teleporting it.
        final half = navWidth / 2;
        final active = current == ShellPage.library ? 0 : 1;

        // Idle: the pill, inset inside the active item's slot. The insets keep
        // it off the item's neighbours and off the rail's top and bottom edges,
        // so it reads as a highlight under the icon and label.
        //
        // Expanded: the same pill stretched to the rail's width to become the
        // search field's background. Only left and width grow; the vertical
        // inset is kept, so the field keeps the button's height instead of
        // becoming a bar the full height of the rail.
        //
        // Position and growth are two springs rather than one interpolation:
        // tapping a destination slides the pill, tapping search grows it, and
        // doing either mid-flight retargets the same physics from wherever the
        // pill is on screen. The slight overshoot is the momentum spring doing
        // its job, clipped by the rail's own stack rather than escaping it.
        return SpringValue(
          value: active.toDouble(),
          spring: FathomMotion.momentum,
          builder: (context, activeT) {
            return SpringValue(
              value: expanded ? 1.0 : 0.0,
              spring: FathomMotion.momentum,
              builder: (context, expandT) {
                final left =
                    (navLeft + activeT * half + kPillInset) * (1 - expandT);
                final width = half -
                    kPillInset * 2 +
                    (totalWidth - half + kPillInset * 2) * expandT;

                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      width: width,
                      // Constant in both states, hence the shared inset: the
                      // pill and the search background are the same height, so
                      // expanding reads as the pill sliding wide rather than
                      // the box changing shape.
                      top: kPillInset,
                      bottom: kPillInset,
                      child: AnimatedContainer(
                        // Slow enough to follow the accent swatch changing in
                        // settings without lagging behind the position
                        // animation.
                        duration: const Duration(milliseconds: 280),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// One destination: an icon over a label, lit when it is the page on screen.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active
        ? FathomColors.onSurface
        : FathomColors.onSurface.withValues(alpha: 0.5);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
