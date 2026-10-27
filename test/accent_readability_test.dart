import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:fathom/common/colors.dart';

/// Accents are painted as text, icons and thin strokes on the page background,
/// so a seed is only a starting point. These tests pin the band that keeps an
/// accent legible in each theme, and the hue that must survive the clamp.
void main() {
  const seeds = [
    Color(0xFF101010),
    Color(0xFF138085),
    Color(0xFF544667),
    Color(0xFFFFFFFF),
  ];

  test('dark accents clear the minimum tone and stay recognisable', () {
    FathomColors.updateBrightness(Brightness.dark);
    addTearDown(() => FathomColors.updateBrightness(Brightness.dark));

    for (final seed in seeds) {
      final accent = FathomColors.readableAccent(seed);
      final hct = Hct.fromInt(accent.toARGB32());
      final source = Hct.fromInt(seed.toARGB32());

      expect(hct.tone, greaterThanOrEqualTo(67.5),
          reason: '$seed must not sink into the dark background');
      // A grey has no meaningful hue to preserve; its HCT hue is noise at
      // zero chroma. Only chromatic seeds carry a hue worth protecting.
      if (source.chroma > 5) {
        expect(
          hct.hue,
          closeTo(source.hue, 3),
          reason: '$seed lost its hue to the clamp',
        );
      }
    }
  });

  test('light accents stay below the maximum tone and stay recognisable', () {
    FathomColors.updateBrightness(Brightness.light);
    addTearDown(() => FathomColors.updateBrightness(Brightness.dark));

    for (final seed in seeds) {
      final accent = FathomColors.readableAccent(seed);
      final hct = Hct.fromInt(accent.toARGB32());
      final source = Hct.fromInt(seed.toARGB32());

      expect(hct.tone, lessThanOrEqualTo(46.5),
          reason: '$seed must not wash out on the light background');
      if (source.chroma > 5) {
        expect(
          hct.hue,
          closeTo(source.hue, 3),
          reason: '$seed lost its hue to the clamp',
        );
      }
    }
  });

  test('both themes keep body-text contrast against the background', () {
    for (final brightness in Brightness.values) {
      FathomColors.updateBrightness(brightness);
      final background = FathomColors.background.computeLuminance();

      for (final seed in seeds) {
        final accent = FathomColors.readableAccent(seed);
        final foreground = accent.computeLuminance();
        final ratio = (foreground > background)
            ? (foreground + 0.05) / (background + 0.05)
            : (background + 0.05) / (foreground + 0.05);

        expect(ratio, greaterThanOrEqualTo(4.5),
            reason:
                '$seed on $brightness is only ${ratio.toStringAsFixed(2)}:1');
      }
    }

    FathomColors.updateBrightness(Brightness.dark);
  });

  test('an accent already inside the band is returned unchanged', () {
    FathomColors.updateBrightness(Brightness.dark);
    addTearDown(() => FathomColors.updateBrightness(Brightness.dark));

    const white = Color(0xFFFFFFFF);
    expect(FathomColors.readableAccent(white), white);
  });
}
