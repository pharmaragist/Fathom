import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/colors.dart';

/// Minimal flat slider primitive.
///
/// Renders a thin rounded track with an accent fill spanning [origin]..[value].
/// A non-zero [origin] lets bipolar controls such as the equalizer bands
/// reference 0 dB instead of the low edge.
class FlatSlider extends StatefulWidget {
  const FlatSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.color,
    this.enabled = true,
    this.vertical = false,
    this.origin = 0,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeOutCubic,
  });

  /// Normalised value, 0..1.
  final double value;

  /// Normalised origin the fill grows from, 0..1.
  final double origin;

  /// When true the slider reads bottom-to-top instead of left-to-right.
  final bool vertical;

  final Color color;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  State<FlatSlider> createState() => _FlatSliderState();
}

class _FlatSliderState extends State<FlatSlider> {
  static const double _tapExtent = 30;
  static const double _trackThickness = 6;
  static const double _activeThickness = 12;

  bool _active = false;
  double _last = 0;

  double _ratio(Offset local, Size size) {
    final extent = widget.vertical ? size.height : size.width;
    if (!extent.isFinite || extent <= 0) return 0;
    final raw = widget.vertical ? 1 - local.dy / extent : local.dx / extent;
    return raw.clamp(0.0, 1.0).toDouble();
  }

  void _begin(Offset local, Size size) {
    if (!widget.enabled) return;
    _last = _ratio(local, size);
    setState(() => _active = true);
    widget.onChanged(_last);
  }

  void _update(Offset local, Size size) {
    if (!widget.enabled) return;
    _last = _ratio(local, size);
    widget.onChanged(_last);
  }

  void _end() {
    if (!widget.enabled) return;
    setState(() => _active = false);
    widget.onChangeEnd(_last);
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.vertical;
    final origin = widget.origin.clamp(0.0, 1.0).toDouble();
    final target = widget.value.clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _begin(d.localPosition, size),
          onTapUp: (_) => _end(),
          onTapCancel: () {
            if (_active) setState(() => _active = false);
          },
          onHorizontalDragStart:
              vertical ? null : (d) => _begin(d.localPosition, size),
          onHorizontalDragUpdate:
              vertical ? null : (d) => _update(d.localPosition, size),
          onHorizontalDragEnd: vertical ? null : (_) => _end(),
          onVerticalDragStart:
              vertical ? (d) => _begin(d.localPosition, size) : null,
          onVerticalDragUpdate:
              vertical ? (d) => _update(d.localPosition, size) : null,
          onVerticalDragEnd: vertical ? (_) => _end() : null,
          child: SizedBox(
            height: vertical ? null : _tapExtent,
            width: vertical ? _tapExtent : null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: vertical
                    ? null
                    : (_active ? _activeThickness : _trackThickness),
                width: vertical
                    ? (_active ? _activeThickness : _trackThickness)
                    : null,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: FathomColors.fill,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Align(
                  child: LayoutBuilder(
                    builder: (context, track) {
                      final span = vertical ? track.maxHeight : track.maxWidth;
                      return TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: target),
                        duration:
                            _active ? Duration.zero : widget.animationDuration,
                        curve: widget.animationCurve,
                        builder: (context, value, _) {
                          final lo = math.min(value, origin) * span;
                          final hi = math.max(value, origin) * span;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: vertical ? 0 : lo,
                                right: vertical ? 0 : null,
                                top: vertical ? null : 0,
                                bottom: vertical ? lo : 0,
                                width: vertical ? null : hi - lo,
                                height: vertical ? hi - lo : null,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: widget.color,
                                    borderRadius: BorderRadius.circular(99),
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
          ),
        );
      },
    );
  }
}
