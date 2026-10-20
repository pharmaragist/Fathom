import 'dart:async';

import 'package:flutter/material.dart';

import '../common/colors.dart';
import 'glass.dart';

class StyledListView<T extends Object> extends StatefulWidget {
  const StyledListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.labelFor,
    required this.accent,
    this.sectionFor,
    this.scrollController,
    this.minItemHeight = 38.0,
    this.maxItemHeight = 90.0,
    this.initialItemHeight = 90.0,
    this.topInset = 4.0,
    this.bottomInset = 150.0,
    this.resizeDuration = const Duration(milliseconds: 220),
    this.enterDuration = const Duration(milliseconds: 520),
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index, double height)
      itemBuilder;
  final String? Function(int index) labelFor;

  /// Names the section an item belongs to, so a merged list can show where one
  /// collection stops and the next starts. Null, the default, renders the list
  /// as one unbroken run exactly as before. Consecutive equal labels collapse
  /// into a single section, so this is read per index but costs one section per
  /// change, not one per row.
  final String? Function(int index)? sectionFor;

  final Color accent;
  final ScrollController? scrollController;
  final double minItemHeight;
  final double maxItemHeight;
  final double initialItemHeight;
  final double topInset;
  final double bottomInset;
  final Duration resizeDuration;
  final Duration enterDuration;

  @override
  State<StyledListView<T>> createState() => _StyledListViewState<T>();
}

class _StyledListViewState<T extends Object> extends State<StyledListView<T>>
    with SingleTickerProviderStateMixin {
  final ScrollController _internalScroll = ScrollController();
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: widget.enterDuration,
  );
  late double _itemHeight = widget.initialItemHeight;
  int _staggerBase = 0;

  ScrollController get _scroll => widget.scrollController ?? _internalScroll;

  @override
  void initState() {
    super.initState();
    _enter.forward();
  }

  @override
  void didUpdateWidget(StyledListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.items, widget.items)) return;
    final first =
        _scroll.hasClients ? (_scroll.offset / _itemHeight).floor() : 0;
    _staggerBase = first < 0 ? 0 : first;
    _enter.forward(from: 0);
  }

  void _setHeight(double value) {
    if (_itemHeight == value) return;
    setState(() => _itemHeight = value);
  }

  @override
  void dispose() {
    _enter.dispose();
    _internalScroll.dispose();
    super.dispose();
  }

  /// Groups [items] into runs sharing one section label, preserving order.
  List<_Section> _sections() {
    final items = widget.items;
    final sectionFor = widget.sectionFor;
    if (sectionFor == null || items.isEmpty) {
      return [_Section(null, 0, items.length)];
    }

    final out = <_Section>[];
    var i = 0;
    while (i < items.length) {
      final label = sectionFor(i);
      var j = i + 1;
      while (j < items.length && sectionFor(j) == label) {
        j++;
      }
      out.add(_Section(label, i, j));
      i = j;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return GestureDetector(
      onDoubleTap: () => _setHeight(widget.maxItemHeight),
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        if (d.scale < 0.85) {
          _setHeight(widget.minItemHeight);
        } else if (d.scale > 1.15) {
          _setHeight(widget.maxItemHeight);
        }
      },
      child: _FastScrollbar(
        controller: _scroll,
        accent: widget.accent,
        itemCount: widget.items.length,
        topInset: widget.topInset,
        bottomInset: widget.bottomInset - 20,
        labelFor: widget.labelFor,
        child: CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // Each section owns its own extent animation; they share duration
            // and curve, so they resize as one list rather than as parts.
            for (var s = 0; s < sections.length; s++)
              ..._sectionSlivers(sections[s],
                  isFirst: s == 0, isLast: s == sections.length - 1),
          ],
        ),
      ),
    );
  }

  List<Widget> _sectionSlivers(
    _Section section, {
    required bool isFirst,
    required bool isLast,
  }) {
    if (section.label != null) {
      // The list sits behind the rail, so section labels need the same
      // horizontal padding the tiles carry to line up with their text.
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, isFirst ? 4 : 18, 24, 6),
            child: Text(
              section.label!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: FathomColors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        _extentSliver(section, isFirst: isFirst, isLast: isLast),
      ];
    }
    return [_extentSliver(section, isFirst: isFirst, isLast: isLast)];
  }

  Widget _extentSliver(
    _Section section, {
    required bool isFirst,
    required bool isLast,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _itemHeight),
      duration: widget.resizeDuration,
      curve: Curves.easeOutCubic,
      builder: (context, extent, _) {
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(
            4,
            isFirst ? widget.topInset : 0,
            4,
            isLast ? widget.bottomInset : 0,
          ),
          sliver: SliverFixedExtentList(
            itemExtent: extent,
            delegate: SliverChildBuilderDelegate(
              (context, k) {
                final i = section.start + k;
                return _EntranceTile(
                  animation: _enter,
                  rank: i - _staggerBase,
                  child:
                      widget.itemBuilder(context, widget.items[i], i, extent),
                );
              },
              childCount: section.end - section.start,
              addAutomaticKeepAlives: false,
              addSemanticIndexes: false,
            ),
          ),
        );
      },
    );
  }
}

/// One run of consecutive items sharing a label.
class _Section {
  const _Section(this.label, this.start, this.end);

  final String? label;
  final int start;

  /// Exclusive, so `end - start` is the section's length.
  final int end;
}

class _EntranceTile extends StatelessWidget {
  const _EntranceTile({
    required this.animation,
    required this.rank,
    required this.child,
  });

  static const _maxRank = 8;
  static const _stagger = 0.06;
  static const _span = 0.52;
  static const _lift = 18.0;

  final Animation<double> animation;
  final int rank;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final step = rank < 0 ? 0 : (rank > _maxRank ? _maxRank : rank);
    final begin = step * _stagger;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final raw = ((animation.value - begin) / _span).clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * _lift),
            child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
          ),
        );
      },
    );
  }
}

class _FastScrollbar extends StatefulWidget {
  const _FastScrollbar({
    required this.controller,
    required this.accent,
    required this.itemCount,
    required this.labelFor,
    required this.child,
    required this.topInset,
    required this.bottomInset,
  });

  final ScrollController controller;
  final Color accent;
  final int itemCount;
  final String? Function(int index) labelFor;
  final Widget child;
  final double topInset;
  final double bottomInset;

  @override
  State<_FastScrollbar> createState() => _FastScrollbarState();
}

class _FastScrollbarState extends State<_FastScrollbar> {
  static const _hideDelay = Duration(milliseconds: 1400);

  Timer? _hideTimer;
  bool _visible = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_FastScrollbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && !_dragging) setState(() => _visible = false);
    });
  }

  void _onScroll() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    if (!_dragging) _scheduleHide();
  }

  void _dragStart() {
    _hideTimer?.cancel();
    setState(() {
      _dragging = true;
      _visible = true;
    });
  }

  void _dragEnd() {
    setState(() => _dragging = false);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final onAccent = FathomColors.onAccent(accent);
    final shown = _visible || _dragging;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: widget.topInset,
          bottom: widget.bottomInset,
          right: 0,
          width: 40,
          child: IgnorePointer(
            ignoring: !shown,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: LayoutBuilder(
                builder: (context, c) {
                  return AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) {
                      if (!widget.controller.hasClients) {
                        return const SizedBox.shrink();
                      }
                      final pos = widget.controller.position;
                      if (!pos.hasContentDimensions ||
                          pos.maxScrollExtent <= 0) {
                        return const SizedBox.shrink();
                      }

                      final max = pos.maxScrollExtent;
                      final viewport = pos.viewportDimension;
                      final trackHeight = c.maxHeight;
                      final thumbHeight =
                          (trackHeight * viewport / (viewport + max))
                              .clamp(56.0, trackHeight);
                      final range = trackHeight - thumbHeight;
                      final fraction = (pos.pixels / max).clamp(0.0, 1.0);
                      final thumbTop = fraction * range;
                      final index = widget.itemCount <= 1
                          ? 0
                          : (fraction * (widget.itemCount - 1)).round();
                      final label = _dragging ? widget.labelFor(index) : null;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (label != null)
                            Positioned(
                              top: thumbTop + thumbHeight / 2 - 26,
                              right: 44,
                              child: GlassContainer(
                                radius: 18,
                                bgOpacity: 0.85,
                                accent: accent,
                                shadow: true,
                                child: SizedBox.square(
                                  dimension: 52,
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: onAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: thumbTop,
                            right: 0,
                            width: 40,
                            height: thumbHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: (_) => _dragStart(),
                              onVerticalDragUpdate: (d) {
                                if (range <= 0) return;
                                final next =
                                    (pos.pixels + d.delta.dy / range * max)
                                        .clamp(0.0, max);
                                widget.controller.jumpTo(next);
                              },
                              onVerticalDragEnd: (_) => _dragEnd(),
                              onVerticalDragCancel: _dragEnd,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: _dragging ? 8 : 4,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color: _dragging
                                        ? accent
                                        : FathomColors.onSurface
                                            .withValues(alpha: 0.32),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
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
        ),
      ],
    );
  }
}
