import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// One generated Material 3 palette for one [brightness].
///
/// The palette is always monochrome: Fathom's surfaces are near-grey and the
/// accent is the only chromatic token. Foreground tiers are alpha steps of
/// `onSurface`, and the media tier stays chroma-free because it sits on artwork.
class FathomPalette {
  FathomPalette._(this.brightness)
      : _neutral = _neutralPalette,
        _media = TonalPalette.of(_seedHct.hue, 0);

  /// The fixed brand seed. It is not the accent; accents are chosen separately.
  static const Color seed = Color(0xFFDC8666);

  static final Hct _seedHct = Hct.fromInt(seed.toARGB32());

  /// Material's monochrome neutral ladder.
  static final TonalPalette _neutralPalette = SchemeMonochrome(
    sourceColorHct: _seedHct,
    isDark: false,
    contrastLevel: 0,
  ).neutralPalette;

  static final TonalPalette _errorPalette = TonalPalette.of(25, 80);
  static final TonalPalette _warningPalette = TonalPalette.of(40, 100);

  /// Surfaces: the neutral ladder, read as depth, not hue.
  final TonalPalette _neutral;

  /// Zero chroma: text over artwork must never take a tint from the theme.
  final TonalPalette _media;

  static final Map<Brightness, FathomPalette> _cache = {};

  /// The palette for [brightness], built once and reused.
  static FathomPalette of(Brightness brightness) =>
      _cache.putIfAbsent(brightness, () => FathomPalette._(brightness));

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

  /// The tone band an accent must sit in to stay legible on this palette.
  ///
  /// Accents are used as text, icons and thin strokes on [background], not only
  /// as fills behind ink, so a seed is only a starting point: a dark seed on a
  /// dark surface disappears, and a pale seed on a light surface does too.
  /// Dark lifts every accent to at least tone 68 (about 7:1 on the tone-2
  /// background); light pulls every accent down to at most tone 46 (about
  /// 4.6:1 on the tone-99 background). Both are HCT tones, so hue survives.
  double get _accentFloor => _isDark ? 68 : 0;
  double get _accentCeiling => _isDark ? 100 : 46;

  /// [seed] with its tone clamped into the band that reads against [background].
  ///
  /// Only the tone moves: hue and chroma are the accent's identity, and a
  /// custom seed should still look like itself after the clamp. A seed already
  /// inside the band is returned untouched, so the common case allocates
  /// nothing. Results are cached per seed because this runs during builds —
  /// every row that paints the accent would otherwise pay an HCT conversion.
  Color readableAccent(Color seed) {
    final argb = seed.toARGB32();
    final cached = _readableAccents[argb];
    if (cached != null) return cached;
    final hct = Hct.fromInt(argb);
    final tone = hct.tone.clamp(_accentFloor, _accentCeiling);
    final result = (tone - hct.tone).abs() < 0.5
        ? seed
        : Color(Hct.from(hct.hue, hct.chroma, tone).toInt());
    return _readableAccents[argb] = result;
  }

  /// Ink for content sitting on [accent]: white on a dark accent, black on a
  /// light one, decided by the accent's own HCT tone rather than per widget.
  Color onAccent(Color accent) {
    final argb = accent.toARGB32();
    final cached = _accentInks[argb];
    if (cached != null) return cached;
    final ink =
        Color(Hct.fromInt(argb).tone < 50 ? _media.get(100) : _media.get(0));
    return _accentInks[argb] = ink;
  }

  final Map<int, Color> _readableAccents = {};
  final Map<int, Color> _accentInks = {};
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
  ///
  /// Four deliberate basics: paper white, the brand terracotta, deep teal and
  /// aubergine. Custom seeds still append after these; the built-in list stays
  /// short so the accent sheet is a choice, not a color catalogue.
  static const List<Color> accentSwatches = [
    Color(0xFFFFFFFF),
    Color(0xFFDC8666),
    Color(0xFF138085),
    Color(0xFF544667),
  ];

  static Brightness _brightness = Brightness.dark;

  /// Whether the dark theme paints pure black. Written by `FathomApp.build`.
  static bool _amoled = false;

  /// The palette the app is currently painted with.
  static FathomPalette get palette => FathomPalette.of(_brightness);
  static Brightness get brightness => _brightness;

  /// Points every token at the palette for [value]. Called by `FathomApp`
  /// before it builds the subtree, so one theme change repaints everything.
  static void updateBrightness(Brightness value) => _brightness = value;

  /// Whether the dark background is pure black.
  static void updateAmoled(bool value) => _amoled = value;

  /// The brightness a [ThemeMode] resolves to right now: light and dark are
  /// fixed, system follows the device's own day/night setting.
  static Brightness resolve(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      };

  // Surfaces.
  static Color get background => _amoled && _brightness == Brightness.dark
      ? palette.mediaBackground
      : palette.background;

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

  /// [seed] clamped to an accent that stays legible on the active background.
  ///
  /// This is the accent every surface should paint: see
  /// [FathomPalette.readableAccent]. The raw seed remains available through
  /// `FathomSettings.accentSeeds`, which is what the picker renders.
  static Color readableAccent(Color seed) => palette.readableAccent(seed);

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
