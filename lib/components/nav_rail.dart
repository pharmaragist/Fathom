import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import '../states.dart';

const double kPillHeight = 64;
const double kHorizontalMargin = 4;
const double kElevationMargin = 6;
const double kNavBarHeight = 64;

class FloatingNavRail extends StatelessWidget {
  const FloatingNavRail({
    super.key,
    required this.index,
    required this.accent,
    required this.bottomSafe,
    required this.onChanged,
  });

  final int index;
  final Color accent;
  final double bottomSafe;
  final ValueChanged<int> onChanged;

  static const _items = [
    (label: 'Library', icon: TablerIcons.discFilled),
   (label: 'Equalizer', icon: TablerIcons.waveSine),
  ];

  @override
  Widget build(BuildContext context) {
    final notchDepth = kPillHeight / 2 + kElevationMargin;
    final count = _items.length;
    final alignX = count == 1 ? 0.0 : -1 + 2 * index / (count - 1);

    return SizedBox(
      width: double.infinity,
      height: notchDepth + kNavBarHeight + bottomSafe,
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
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutBack,
                    alignment: Alignment(alignX, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / count,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: _NavItem(
                              label: _items[i].label,
                              icon: _items[i].icon,
                              selected: index == i,
                              accent: accent,
                              onTap: () => onChanged(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
