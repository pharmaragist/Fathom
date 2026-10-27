import 'dart:async';

import 'package:flutter/material.dart';

import '../common/colors.dart';
import '../common/motion.dart';
import 'glass.dart';

/// Exposes the list's zoom step to a row that owns its own tap gesture.
///
/// A row's [InkWell] and the list-level double-tap detector cannot both own the
/// gesture: the row would start playback on the first tap before the list could
/// see a second. Rows that know about this scope put the same callback on their
/// own detector, so the tap and double tap are arbitrated in one place and a
/// double tap zooms instead of opening the row.
class StyledListZoom extends InheritedWidget {
  const StyledListZoom({
    super.key,
    required this.onDoubleTap,
    required super.child,
  });

  final VoidCallback onDoubleTap;

  static StyledListZoom? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<StyledListZoom>();
  }

  @override
  bool updateShouldNotify(StyledListZoom oldWidget) =>
      oldWidget.onDoubleTap != onDoubleTap;
}

class StyledListView<T extends Object> extends StatefulWidget {
  const StyledListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.labelFor,
    required this.accent,
    this.keyFor,
    this.sectionFor,
    this.scrollController,
    this.minItemHeight = 38.0,
    this.maxItemHeight = 90.0,
    this.initialItemHeight = 90.0,
    this.zoomStages,
    this.topInset = 4.0,
    this.bottomInset = 150.0,
    this.enterDuration = const Duration(milliseconds: 520),
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index, double height)
      itemBuilder;
  final String? Function(int index) labelFor;

  /// The stable identity of the row at [index], used as its widget key.
  ///
  /// A list that changes one row at a time should provide this. With a key the
  /// sliver can match a row to its existing element when its index shifts
  /// (through `findChildIndexCallback` below), so an insert at the top does not
  /// rebuild every row beneath it and does not restart their entrance
  /// animation. Return null and the list falls back to the old index-keyed
  /// behaviour, where any structural change is treated as a reload.
  final Key? Function(int index)? keyFor;

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

  /// The row heights a pinch or double tap snaps to, smallest first.
  ///
  /// Null keeps the old two-state behaviour of [minItemHeight] and
  /// [maxItemHeight]. A surface that offers zoom stages passes the whole
  /// ladder; the list only owns the gesture, not the row's internal layout.
  final List<double>? zoomStages;
  final double topInset;
  final double bottomInset;
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

  /// Height at the start of a pinch, and whether two pointers actually moved.
  /// A one-finger drag must reach the scroll view without resizing a row.
  double? _pinchStartHeight;
  bool _pinched = false;

  /// False while the finger is changing the extent, so the list follows it
  /// immediately; true when a stage snap should animate.
  bool _animateHeight = true;

  /// The snap ladder, sorted and free of invalid values.
  List<double> get _zoomStages {
    final custom = widget.zoomStages;
    if (custom == null || custom.isEmpty) {
      return [widget.minItemHeight, widget.maxItemHeight];
    }
    final stages = [
      for (final value in custom)
        if (value.isFinite && value > 0) value,
    ]..sort();
    if (stages.isEmpty) return [widget.minItemHeight, widget.maxItemHeight];
    return stages;
  }

  /// The keys the list held at the previous build. Null when the caller does
  /// not supply [StyledListView.keyFor], which keeps the old index-keyed path.
  Set<Key>? _knownKeys;

  /// Keys added since the previous build. Only these rows run a local entrance;
  /// every surviving row keeps whatever opacity it already has.
  Set<Key> _entering = const <Key>{};

  ScrollController get _scroll => widget.scrollController ?? _internalScroll;

  @override
  void initState() {
    super.initState();
    _knownKeys = widget.keyFor == null ? null : _keysOf(widget);
    _enter.forward();
  }

  Set<Key> _keysOf(StyledListView<T> list) {
    final keyFor = list.keyFor;
    if (keyFor == null) return const <Key>{};
    final keys = <Key>{};
    for (var i = 0; i < list.items.length; i++) {
      final key = keyFor(i);
      if (key != null) keys.add(key);
    }
    return keys;
  }

  int _firstVisibleIndex() {
    if (!_scroll.hasClients) return 0;
    final first = (_scroll.offset / _itemHeight).floor();
    return first < 0 ? 0 : first;
  }

  @override
  void didUpdateWidget(StyledListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.items, widget.items)) return;
    if (widget.keyFor != null) {
      _adoptKeyedChange();
      return;
    }
    final oldItems = oldWidget.items;
    final newItems = widget.items;
    // Only restart entrance animation on structural changes, not appends
    var isPureAppend = newItems.length >= oldItems.length;
    if (isPureAppend) {
      for (var i = 0; i < oldItems.length; i++) {
        if (!identical(newItems[i], oldItems[i])) {
          isPureAppend = false;
          break;
        }
      }
    } else {
      isPureAppend = false;
    }
    if (isPureAppend) {
      // Just update stagger base for new items without restarting animation
      _staggerBase = _firstVisibleIndex();
      return;
    }
    _staggerBase = _firstVisibleIndex();
    _enter.forward(from: 0);
  }

  /// Adopts a change between two keyed lists.
  ///
  /// The distinction that matters is whether anything survived. If every row
  /// is new — first content, or a wholly different query result — the shared
  /// cascade is right. If only some rows are new, restarting it would replay
  /// the entrance over rows the user is already reading, so the survivors are
  /// left alone and the new keys animate individually.
  ///
  /// Removal is deliberately not animated. A sliver has no exit phase; holding
  /// a removed row on screen would need a separate overlay list, which is a new
  /// scrolling architecture rather than a key change. The row therefore leaves
  /// immediately while every survivor keeps its element and its position.
  void _adoptKeyedChange() {
    final oldKeys = _knownKeys ?? const <Key>{};
    final newKeys = _keysOf(widget);
    final added = <Key>{
      for (final key in newKeys)
        if (!oldKeys.contains(key)) key,
    };
    _knownKeys = newKeys;
    _staggerBase = _firstVisibleIndex();

    if (newKeys.isEmpty) {
      _entering = const <Key>{};
      return;
    }
    if (oldKeys.isEmpty || added.length == newKeys.length) {
      _entering = const <Key>{};
      _enter.forward(from: 0);
      return;
    }
    _entering = added;
  }

  void _setHeight(double value, {bool animate = true}) {
    final stages = _zoomStages;
    final clamped = value.clamp(stages.first, stages.last).toDouble();
    if (_itemHeight == clamped) return;
    setState(() {
      _itemHeight = clamped;
      _animateHeight = animate;
    });
  }

  /// The stage whose height is nearest the current one.
  int _nearestStage(List<double> stages) {
    var nearest = 0;
    var best = (_itemHeight - stages[0]).abs();
    for (var i = 1; i < stages.length; i++) {
      final distance = (_itemHeight - stages[i]).abs();
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    }
    return nearest;
  }

  /// Double tap steps up one stage and wraps from the largest to the smallest.
  void _cycleStage() {
    final stages = _zoomStages;
    if (stages.length < 2) {
      _setHeight(widget.maxItemHeight);
      return;
    }
    final next = (_nearestStage(stages) + 1) % stages.length;
    _setHeight(stages[next]);
  }

  /// A pinch ends on a stage rather than between two, so text and art always
  /// land on a layout the list can cache and the next gesture can name.
  void _snapToStage() {
    final stages = _zoomStages;
    if (stages.length < 2) return;
    _setHeight(stages[_nearestStage(stages)]);
  }

  void _scaleStart(ScaleStartDetails details) {
    _pinchStartHeight = _itemHeight;
    _pinched = false;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    final base = _pinchStartHeight ?? _itemHeight;
    _pinched = true;
    _setHeight(base * details.scale, animate: false);
  }

  void _scaleEnd(ScaleEndDetails details) {
    if (_pinched) _snapToStage();
    _pinchStartHeight = null;
    _pinched = false;
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
    final keyFor = widget.keyFor;
    Map<Key, int>? keyIndices;
    if (keyFor != null) {
      keyIndices = <Key, int>{};
      for (var i = 0; i < widget.items.length; i++) {
        final key = keyFor(i);
        if (key != null) keyIndices[key] = i;
      }
    }
    return GestureDetector(
      onDoubleTap: _cycleStage,
      onScaleStart: _scaleStart,
      onScaleUpdate: _scaleUpdate,
      onScaleEnd: _scaleEnd,
      child: StyledListZoom(
        onDoubleTap: _cycleStage,
        child: _FastScrollbar(
          controller: _scroll,
          accent: widget.accent,
          itemCount: widget.items.length,
          topInset: widget.topInset,
          bottomInset: widget.bottomInset - 20,
          labelFor: widget.labelFor,
          child: _EdgeFade(
            // The fade has to sit away from the list's own insets, or the first
            // and last rows would start fading while they are still the things
            // the eye is on.
            firstFade: widget.topInset + 28,
            lastFade: widget.bottomInset + 28,
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                // Each section owns its own extent animation; they share duration
                // and curve, so they resize as one list rather than as parts.
                for (var s = 0; s < sections.length; s++)
                  ..._sectionSlivers(
                    sections[s],
                    isFirst: s == 0,
                    isLast: s == sections.length - 1,
                    keyIndices: keyIndices,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sectionSlivers(
    _Section section, {
    required bool isFirst,
    required bool isLast,
    required Map<Key, int>? keyIndices,
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
        _extentSliver(section,
            isFirst: isFirst, isLast: isLast, keyIndices: keyIndices),
      ];
    }
    return [
      _extentSliver(section,
          isFirst: isFirst, isLast: isLast, keyIndices: keyIndices),
    ];
  }

  Widget _extentSliver(
    _Section section, {
    required bool isFirst,
    required bool isLast,
    required Map<Key, int>? keyIndices,
  }) {
    return SpringValue(
      value: _itemHeight,
      immediate: !_animateHeight,
      spring: FathomMotion.snap,
      builder: (context, extent) {
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
                final rowKey = widget.keyFor?.call(i);
                return _EntranceTile(
                  key: rowKey,
                  animation: _enter,
                  rank: i - _staggerBase,
                  entering: rowKey != null && _entering.contains(rowKey),
                  enterDuration: widget.enterDuration,
                  child:
                      widget.itemBuilder(context, widget.items[i], i, extent),
                );
              },
              childCount: section.end - section.start,
              addAutomaticKeepAlives: false,
              addSemanticIndexes: false,
              // A keyed row that moved index is the same row. Returning its
              // new index lets the sliver move the existing element instead of
              // replacing it, which is what preserves scroll anchoring, row
              // state and a finished entrance animation across a delta.
              findChildIndexCallback: keyIndices == null
                  ? null
                  : (key) {
                      final global = keyIndices[key];
                      if (global == null) return null;
                      final local = global - section.start;
                      if (local < 0 || local >= section.end - section.start) {
                        return null;
                      }
                      return local;
                    },
            ),
          ),
        );
      },
    );
  }
}

/// Softens the two ends of a scrolling list so rows do not meet a hard edge.
///
/// The list runs the full height of the shell layer, straight under the header
/// at the top and behind the mini player and rail at the bottom. Without this a
/// row scrolled to either end is sliced off flush by whatever it passes behind,
/// which reads as a blunt edge rather than as content that has scrolled away.
/// Fading it out says the same thing without the cut.
///
/// This is a [ShaderMask] over a linear alpha gradient rather than a [ClipRRect].
/// Both cost a compositing layer, so the choice is not about avoiding one
/// wholesale — it is about what the layer has to compute and what it cuts. A
/// rounded clip has to anti-alias a curved edge and cuts pixels hard on that
/// curve, so a row crossing it is severed along a shape it has nothing to do
/// with, and the translucent rows behind it are left fighting the boundary. The
/// shader instead writes a per-pixel alpha ramp: no curved geometry, and the
/// transition is a gradient, so a row is faded rather than severed and there is
/// no boundary for a translucent tile to disagree with.
///
/// The masked region is deliberately a *plain* rectangle covering only the
/// scrolling rows. The fast scrollbar and its letter label live outside this
/// widget, in the [Stack] above, so neither is faded and the label can still
/// overhang the list as it was designed to.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({
    required this.child,
    required this.firstFade,
    required this.lastFade,
  });

  final Widget child;

  /// Height of the top falloff, measured from the top of the layer.
  final double firstFade;

  /// Height of the bottom falloff, measured from the bottom of the layer.
  final double lastFade;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        // A short viewport (a keyboard, a very small window) can have the two
        // ramps meet, which would leave the middle of the list invisible. The
        // mask then degenerates to fully opaque and the list is simply not
        // faded — the honest failure, since the alternative is hiding content.
        if (!height.isFinite || height <= 0 || firstFade + lastFade >= height) {
          return child;
        }

        return ShaderMask(
          // `srcIn` keeps the child's own alpha and multiplies it by the
          // shader's, so a tile that is already translucent (an entrance
          // animation mid-flight) fades from where it is rather than being
          // forced opaque first.
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: [
              0,
              firstFade / height,
              1 - (lastFade / height),
              1,
            ],
          ).createShader(bounds),
          child: child,
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
    super.key,
    required this.animation,
    required this.rank,
    required this.entering,
    required this.enterDuration,
    required this.child,
  });

  static const _maxRank = 8;
  static const _stagger = 0.06;
  static const _span = 0.52;
  static const _lift = 18.0;

  final Animation<double> animation;
  final int rank;

  /// True for a row added to an already-visible list. It runs its own short
  /// entrance instead of the shared cascade, so the rows around it do not
  /// replay theirs.
  final bool entering;
  final Duration enterDuration;
  final Widget child;

  Widget _settle(double t, Widget child) {
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * _lift),
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (entering) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: enterDuration,
        curve: const FathomSpringCurve(),
        child: child,
        builder: (context, t, child) => _settle(t, child!),
      );
    }

    final step = rank < 0 ? 0 : (rank > _maxRank ? _maxRank : rank);
    final begin = step * _stagger;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final raw = ((animation.value - begin) / _span).clamp(0.0, 1.0);
        return _settle(const FathomSpringCurve().transform(raw), child!);
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
                      // The minimum thumb is a legibility floor, so it has to
                      // yield to the track: a viewport shorter than the floor
                      // (a small window, a keyboard, split screen) would
                      // otherwise clamp with its lower bound above its upper
                      // one, which throws and takes the whole list down. On a
                      // track that short, a smaller thumb is the honest answer.
                      final thumbHeight = (trackHeight *
                              viewport /
                              (viewport + max))
                          .clamp(trackHeight < 56.0 ? 0.0 : 56.0, trackHeight);
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
                                child: SpringValue(
                                  value: _dragging ? 1.0 : 0.0,
                                  spring: FathomMotion.press,
                                  builder: (context, t) {
                                    final grip = t.clamp(0.0, 1.0);
                                    return Container(
                                      width: 4 + 4 * grip,
                                      margin: const EdgeInsets.only(right: 3),
                                      decoration: BoxDecoration(
                                        color: Color.lerp(
                                          FathomColors.onSurface
                                              .withValues(alpha: 0.32),
                                          accent,
                                          grip,
                                        ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    );
                                  },
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
