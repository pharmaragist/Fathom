import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 16,
    this.bgOpacity = 0.65,
    this.borderOpacity = 0.07,
    this.accent,
    this.padding,
    this.shadow = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final double bgOpacity;
  final double borderOpacity;
  final Color? accent;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  static bool blurEnabled = true;

  static const Color surface = Color(0xFF111111);

  @override
  Widget build(BuildContext context) {
    final effectiveBlur = blurEnabled ? blur : 0.0;

    // Blend accent with white for a crisp frosted edge highlight
    final baseOutline = accent != null
        ? Color.alphaBlend(accent!.withValues(alpha: 0.35), Colors.white)
        : Colors.white;

    Widget content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: bgOpacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: baseOutline.withValues(alpha: borderOpacity),
              width: 1,
            ),
            boxShadow: shadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}
