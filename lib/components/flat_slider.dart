import 'package:flutter/material.dart';

class FlatSlider extends StatefulWidget {
  const FlatSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.color,
    this.onStart,
    this.enabled = true,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeOutCubic,
  });

  final double value;
  final Color color;
  final bool enabled;
  final VoidCallback? onStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  State<FlatSlider> createState() => _FlatSliderState();
}

class _FlatSliderState extends State<FlatSlider> {
  bool _active = false;
  double _last = 0;

  double _ratio(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0).toDouble();

  void _begin(double r) {
    if (!widget.enabled) return;
    widget.onStart?.call();
    _last = r;
    setState(() => _active = true);
    widget.onChanged(r);
  }

  void _update(double r) {
    if (!widget.enabled) return;
    _last = r;
    widget.onChanged(r);
  }

  void _end() {
    if (!widget.enabled) return;
    setState(() => _active = false);
    widget.onChangeEnd(_last);
  }

  @override
  Widget build(BuildContext context) {
    final targetValue = widget.value.clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _begin(_ratio(d.localPosition, w)),
          onTapUp: (_) => _end(),
          onTapCancel: () {
            if (_active) setState(() => _active = false);
          },
          onHorizontalDragStart: (d) => _begin(_ratio(d.localPosition, w)),
          onHorizontalDragUpdate: (d) => _update(_ratio(d.localPosition, w)),
          onHorizontalDragEnd: (_) => _end(),
          child: SizedBox(
            height: 30,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: _active ? 12 : 6,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: targetValue),
                    duration: _active ? Duration.zero : widget.animationDuration,
                    curve: widget.animationCurve,
                    builder: (context, animatedValue, _) {
                      return FractionallySizedBox(
                        widthFactor: animatedValue,
                        child: Container(color: widget.color),
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
