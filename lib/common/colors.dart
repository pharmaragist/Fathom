import 'package:flutter/material.dart';

class FathomColors {
  FathomColors._();

  static const List<Color> accentSwatches = [
    Color(0xFFFFFFFF),
    Color(0xFF0A84FF),
    Color(0xFF64D2FF),
    Color(0xFF30D158),
    Color(0xFFFFD60A),
    Color(0xFFFF9F0A),
    Color(0xFFFF453A),
    Color(0xFFBF5AF2),
    Color(0xFFFF2D55),
  ];

  static const Color background = Colors.black;
  static const Color surface = Colors.black;
  static const Color onSurface = Colors.white;
  static const Color onSurfaceMuted = Colors.white60;

  static Color glassBackground = Colors.white.withValues(alpha: 0.14);
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);
}
