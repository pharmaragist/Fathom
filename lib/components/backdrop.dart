import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/settings.dart';

class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, this.trackId, this.artwork});

  final int? trackId;
  final Future<Uint8List?>? artwork;

  Color _accent(BuildContext context) {
    try {
      return context.select<FathomSettings, Color>((s) => s.accent);
    } on ProviderNotFoundException {
      return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedAccent, _) {
        final color = animatedAccent ?? accent;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -1.2),
              radius: 1.1,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.06),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
