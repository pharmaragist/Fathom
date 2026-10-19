import 'package:flutter/material.dart';

class FathomColors {
  FathomColors._();

  static const List<Color> accentSwatches = [
    Color(0xFFFFFFFF),
    Color(0xFFDC8666),
    Color(0xFF138085),
    Color(0xFF544667),
    Color(0xFFCE7672),
    Color(0xFFEEB462),
    Color(0xFFEEC3BD),
    Color(0xFF364B74),
    Color(0xFF84815C),
    Color(0xFFD1CBC0),
    Color(0xFF4A6B5D),
    Color(0xFF8B5742),
    Color(0xFF9C7A97),
    Color(0xFF6B8496)
  ];

  static const Color background = Colors.black;
  static const Color surface = Colors.black;
  static const Color onSurface = Colors.white;
  static const Color onSurfaceMuted = Colors.white60;

  static Color glassBackground = Colors.white.withValues(alpha: 0.14);
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);
}
