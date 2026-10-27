import 'package:flutter/material.dart';

import '../common/colors.dart';
import '../common/motion.dart';

class FlatIconButton extends StatefulWidget {
  const FlatIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 24.0,
    this.color,
    this.active = false,
    this.activeColor,
    this.enabled = true,
    this.padding = EdgeInsets.zero,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final bool active;
  final Color? activeColor;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  State<FlatIconButton> createState() => _FlatIconButtonState();
}

class _FlatIconButtonState extends State<FlatIconButton> {
  bool _down = false;

  void _handleTapDown(TapDownDetails _) {
    if (widget.enabled) setState(() => _down = true);
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.enabled) setState(() => _down = false);
  }

  void _handleTapCancel() {
    if (widget.enabled) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? FathomColors.onSurface;
    final effectiveColor = widget.active
        ? (widget.activeColor ?? base)
        : (widget.enabled ? base : base.withValues(alpha: 0.24));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.enabled ? widget.onTap : null,
      child: Padding(
        padding: widget.padding,
        // A press is one gesture, so scale and dim share one spring: two timed
        // animations would settle a frame apart and read as two events.
        child: SpringValue(
          value: _down ? 1.0 : 0.0,
          spring: FathomMotion.press,
          builder: (context, t) {
            return Transform.scale(
              scale: 1 - 0.08 * t,
              child: Opacity(
                opacity: (1 - 0.45 * t).clamp(0.0, 1.0),
                child: Icon(
                  widget.icon,
                  size: widget.size,
                  color: effectiveColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
