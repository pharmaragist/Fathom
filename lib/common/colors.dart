import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// One generated Material 3 palette for one [brightness].
///
/// Every tone comes out of `material_color_utilities`: hue and chroma are
/// taken from [seed], and each token below is a tone of a generated
/// [TonalPalette]. Foreground tiers are alpha steps of `onSurface` so they
/// flip from white-on-dark to black-on-light with no per-widget logic, and
/// the media tier stays chroma-free white because it sits on artwork, which
/// can be any color in either theme.
class FathomPalette {
  FathomPalette._(this.brightness);

  /// The seed every neutral, outline and status tone is derived from.
  static const Color seed = Color(0xFFDC8666);

  static final Hct _seedHct = Hct.fromInt(seed.toARGB32());

  /// Surfaces: low chroma, so the tone ladder reads as depth, not as hue.
  static final TonalPalette _neutral = TonalPalette.of(_seedHct.hue, 6);
  static final TonalPalette _errorPalette = TonalPalette.of(25, 80);
  static final TonalPalette _warningPalette = TonalPalette.of(40, 100);

  /// Zero chroma: text over artwork must never take a tint from the theme.
  static final TonalPalette _media = TonalPalette.of(_seedHct.hue, 0);

  static final Map<Brightness, FathomPalette> _cache = {
    for (final value in Brightness.values) value: FathomPalette._(value),
  };

  /// The palette for [brightness], built once and reused.
  static FathomPalette of(Brightness brightness) => _cache[brightness]!;

  final Brightness brightness;
  bool get _isDark => brightness == Brightness.dark;

  Color _tone(int dark, int light) =>
      Color(_neutral.get(_isDark ? dark : light));

  // Surfaces.

  /// The app background behind everything.
  Color get background => _tone(2, 99);

  // Foreground on [background].

  Color get onSurface => _tone(98, 10);

  /// Secondary labels: artist lines, sheet subtitles, section headers.
  Color get onSurfaceMuted => onSurface.withValues(alpha: 0.60);

  /// Tertiary labels: timestamps, hints, inactive controls.
  Color get onSurfaceDim => onSurface.withValues(alpha: 0.42);

  /// Placeholder and disabled: chevrons, badges, empty-state icons.
  Color get onSurfaceFaint => onSurface.withValues(alpha: 0.26);

  // Fills: translucent layers painted on a surface.

  /// Chip and input fills.
  Color get fillFaint => onSurface.withValues(alpha: 0.06);

  /// Dividers inside glass and progress troughs.
  Color get fillLow => onSurface.withValues(alpha: 0.10);

  /// Slider tracks and tint washes.
  Color get fill => onSurface.withValues(alpha: 0.14);

  /// Strong washes: pressed states and dense overlays.
  Color get fillStrong => onSurface.withValues(alpha: 0.22);

  /// The one hairline: section rules and glass outlines.
  Color get hairline => _tone(14, 86);

  // Overlays.

  /// Base black for shadows; callers pick their own alpha.
  Color get shadow => Color(_neutral.get(0));

  /// Modal barriers.
  Color get scrim => shadow.withValues(alpha: 0.60);

  /// The veil over artwork on Now Playing.
  Color get mediaScrim => shadow.withValues(alpha: 0.76);

  // Media tier: constant in both themes, because the Now Playing backdrop is
  // always the artwork under [mediaScrim].

  Color get mediaBackground => Color(_neutral.get(0));
  Color get mediaSurface => Color(_neutral.get(12));
  Color get onMedia => Color(_media.get(100));
  Color get onMediaMuted => onMedia.withValues(alpha: 0.60);

  // Status.

  /// Errors: the destructive red the sheets and equalizer warnings use.
  Color get error => Color(_errorPalette.get(_isDark ? 65 : 40));

  /// Warnings: failed imports, overwrite notices.
  Color get warning => Color(_warningPalette.get(_isDark ? 72 : 45));

  /// Ink for content sitting on [accent]: white on a dark accent, black on a
  /// light one, decided by the accent's own HCT tone rather than per widget.
  Color onAccent(Color accent) => Color(Hct.fromInt(accent.toARGB32()).tone < 50
      ? _media.get(100)
      : _media.get(0));
}

/// The app's color vocabulary.
///
/// Tokens are getters over the active [FathomPalette]; [updateBrightness]
/// swaps the palette when the theme resolves, which `FathomApp` does on every
/// build from the theme mode and the platform brightness. Widgets must read
/// colors from here (or `Theme.of(context).colorScheme`), never from a
/// literal `Color(0x..)`.
class FathomColors {
  FathomColors._();

  /// Accent seed choices offered in Settings. Each is a seed for
  /// `ColorScheme.fromSeed`, not a hand-picked final color.
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

  static Brightness _brightness = Brightness.dark;

  /// The palette the app is currently painted with.
  static FathomPalette get palette => FathomPalette.of(_brightness);
  static Brightness get brightness => _brightness;

  /// Points every token at the palette for [value]. Called by `FathomApp`
  /// before it builds the subtree, so one theme change repaints everything.
  static void updateBrightness(Brightness value) => _brightness = value;

  /// The brightness a [ThemeMode] resolves to right now: light and dark are
  /// fixed, system follows the device's own day/night setting.
  static Brightness resolve(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      };

  // Surfaces.
  static Color get background => palette.background;

  // Foreground.
  static Color get onSurface => palette.onSurface;
  static Color get onSurfaceMuted => palette.onSurfaceMuted;
  static Color get onSurfaceDim => palette.onSurfaceDim;
  static Color get onSurfaceFaint => palette.onSurfaceFaint;

  // Fills and lines.
  static Color get fillFaint => palette.fillFaint;
  static Color get fillLow => palette.fillLow;
  static Color get fill => palette.fill;
  static Color get fillStrong => palette.fillStrong;
  static Color get hairline => palette.hairline;

  // Overlays.
  static Color get shadow => palette.shadow;
  static Color get scrim => palette.scrim;
  static Color get mediaScrim => palette.mediaScrim;

  // Media tier (theme-independent).
  static Color get mediaBackground => palette.mediaBackground;
  static Color get mediaSurface => palette.mediaSurface;
  static Color get onMedia => palette.onMedia;
  static Color get onMediaMuted => palette.onMediaMuted;

  // Status.
  static Color get error => palette.error;
  static Color get warning => palette.warning;

  /// Ink for content on top of an accent color.
  static Color onAccent(Color accent) => palette.onAccent(accent);

  /// Status and navigation bar styling for the active palette.
  static SystemUiOverlayStyle systemUiOverlayStyle() => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            _brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            _brightness == Brightness.dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            _brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      );
}
