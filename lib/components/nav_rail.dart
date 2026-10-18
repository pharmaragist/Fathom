import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

const double kPillHeight = 64;
const double kHorizontalMargin = 4;
const double kElevationMargin = 6;
const double kNavBarHeight = 64;

class FloatingNavRail extends StatefulWidget {
  const FloatingNavRail({
    super.key,
    required this.index,
    required this.accent,
    required this.bottomSafe,
    required this.onChanged,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.sortLabel,
    required this.onSort,
  });

  final int index;
  final Color accent;
  final double bottomSafe;
  final ValueChanged<int> onChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String sortLabel;
  final VoidCallback onSort;

  @override
  State<FloatingNavRail> createState() => _FloatingNavRailState();
}

class _FloatingNavRailState extends State<FloatingNavRail> {
  static const _debounceDuration = Duration(milliseconds: 300);

  bool _isSearching = false;
  Timer? _debounce;

  static const _items = [
    (label: 'Library', icon: TablerIcons.discFilled),
    (label: 'Equalizer', icon: TablerIcons.waveSine),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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
    setState(() => _isSearching = active);
    if (!active) widget.onSearchCleared();
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
    final count = _items.length;

    return SizedBox(
      width: double.infinity,
      height: notchDepth + kNavBarHeight + widget.bottomSafe,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _NotchedNavClipper(),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.04),
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
                  final availableWidth = totalWidth - searchBtnWidth;
                  final itemWidth = availableWidth / count;

                  final double indicatorLeft = _isSearching
                      ? 0.0
                      : searchBtnWidth + (widget.index * itemWidth);
                  final double indicatorWidth =
                      _isSearching ? totalWidth : itemWidth;

                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        left: indicatorLeft,
                        width: indicatorWidth,
                        top: 0,
                        bottom: 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            decoration: BoxDecoration(
                              color: widget.accent
                                  .withValues(alpha: _isSearching ? 0.1 : 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: widget.accent.withValues(
                                    alpha: _isSearching ? 0.35 : 0.0),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: _switcherLayout,
                          child: _isSearching
                              ? _NavSearchContent(
                                  key: const ValueKey('search_mode'),
                                  controller: widget.searchController,
                                  accent: widget.accent,
                                  sortLabel: widget.sortLabel,
                                  onSort: widget.onSort,
                                  onChanged: _onQueryChanged,
                                  onSubmitted: _onQuerySubmitted,
                                  onClose: () => _toggleSearch(false),
                                )
                              : Row(
                                  key: const ValueKey('nav_mode'),
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: searchBtnWidth,
                                      child: IconButton(
                                        icon: const Icon(TablerIcons.search,
                                            size: 20),
                                        color: Colors.white
                                            .withValues(alpha: 0.72),
                                        onPressed: () => _toggleSearch(true),
                                      ),
                                    ),
                                    for (var i = 0; i < count; i++)
                                      Expanded(
                                        child: _NavItem(
                                          label: _items[i].label,
                                          icon: _items[i].icon,
                                          selected: widget.index == i,
                                          accent: widget.accent,
                                          onTap: () => widget.onChanged(i),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ],
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
    required this.sortLabel,
    required this.onSort,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
  });

  final TextEditingController controller;
  final Color accent;
  final String sortLabel;
  final VoidCallback onSort;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClose;

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
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(TablerIcons.search, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
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
              style: const TextStyle(
                fontSize: 14,
                height: 1.2,
                color: Colors.white,
              ),
              cursorColor: accent,
              cursorHeight: 18,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search library',
                hintStyle: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SortChip(label: sortLabel, accent: accent, onTap: onSort),
          const SizedBox(width: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return _RoundIconButton(
                icon: value.text.isEmpty ? TablerIcons.x : TablerIcons.backspace,
                color: Colors.white.withValues(alpha: 0.6),
                onTap: _handleTrailing,
              );
            },
          ),
        ],
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
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final target = selected ? accent : Colors.white.withValues(alpha: 0.72);
    final baseTextStyle = Theme.of(context).textTheme.bodyMedium;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target),
        duration: const Duration(milliseconds: 260),
        builder: (context, color, _) {
          final fg = color ?? target;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                style: (baseTextStyle ?? const TextStyle()).copyWith(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                  letterSpacing: -0.2,
                ),
                child: Text(label),
              ),
            ],
          );
        },
      ),
    );
  }
}
