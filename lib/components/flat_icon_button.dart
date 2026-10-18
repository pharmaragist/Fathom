import 'package:flutter/material.dart';

class FlatIconButton extends StatefulWidget {
  const FlatIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 24.0,
    this.color = Colors.white,
    this.active = false,
    this.activeColor,
    this.enabled = true,
    this.padding = EdgeInsets.zero,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color color;
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
    final effectiveColor = widget.active
        ? (widget.activeColor ?? widget.color)
        : (widget.enabled ? widget.color : widget.color.withValues(alpha: 0.24));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.enabled ? widget.onTap : null,
      child: Padding(
        padding: widget.padding,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _down ? 0.55 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: effectiveColor,
            ),
          ),
        ),
      ),
    );
  }
}
