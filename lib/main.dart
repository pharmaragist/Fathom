import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'common/colors.dart';
import 'common/constants.dart';
import 'common/library.dart';
import 'common/player.dart';
import 'common/search.dart';
import 'common/settings.dart';
import 'components/glass.dart';
import 'content.dart';
import 'pages/onboarding.dart';
import 'services/artwork.dart';
import 'services/downloads.dart';
import 'services/fonts.dart';
import 'services/power.dart';
import 'services/yt_source.dart';

class FathomApp extends StatefulWidget {
  const FathomApp({
    super.key,
    required this.settings,
    required this.player,
    required this.library,
    required this.downloads,
    required this.power,
  });

  final FathomSettings settings;
  final FathomPlayer player;

  /// Built in `main` rather than by the provider tree, because the downloads
  /// service has to rescan this library the moment a file lands.
  final FathomLibrary library;

  final FathomDownloads downloads;

  /// Battery Saver followed live. Built in `main` too, because it is device
  /// state rather than app state: it exists before this widget and is started
  /// with the other services.
  final FathomPowerState power;

  @override
  State<FathomApp> createState() => _FathomAppState();
}

class _FathomAppState extends State<FathomApp> {
  SystemUiOverlayStyle? _lastOverlay;
  VoidCallback? _previousBrightnessHandler;

  /// The settings that can change the app's chrome: the theme, the palette,
  /// the font and the first-run destination.
  ///
  /// Every notification from [FathomSettings] used to rebuild the whole
  /// subtree, so changing the sort order or clearing an EQ preset rebuilt
  /// `MaterialApp` and regenerated its colour scheme. Only these values are
  /// read above the provider tree, so only these may wake it; every other
  /// setting is read by the surface that owns it.
  _Chrome? _chrome;

  /// The last built theme, reused while its inputs are unchanged.
  ///
  /// `ColorScheme.fromSeed` runs a full Material scheme generation and
  /// `ThemeData` resolves the component themes around it, which is far too
  /// much work to repeat for a notification that does not change the theme.
  ThemeData? _theme;
  Color? _themeAccent;
  Brightness? _themeBrightness;
  String? _themeFont;
  bool? _themeAmoled;

  _Chrome _chromeSignature() {
    final settings = widget.settings;
    return (
      brightness: FathomColors.resolve(settings.themeMode),
      themeIndex: settings.get<int>(SettingKey.themeIndex),
      accentIndex: settings.get<int>(SettingKey.accentIndex),
      seedCount: settings.accentSeeds.length,
      amoled: settings.get<bool>(SettingKey.amoled),
      fontKey: settings.get<String>(SettingKey.fontKey),
      lowEnd: settings.get<bool>(SettingKey.lowEnd),
      onboarded: settings.get<bool>(SettingKey.onboarded),
      powerSave: widget.power.isPowerSave,
    );
  }

  /// Rebuilds only when a value read above the provider tree actually changed.
  void _rebuildForTheme() {
    final next = _chromeSignature();
    if (next == _chrome) return;
    _chrome = next;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _chrome = _chromeSignature();
    widget.settings.addListener(_rebuildForTheme);
    // Power save changes the effective low-end state, and therefore the one
    // write of `GlassContainer.blurEnabled` below, so it needs the same kind of
    // rebuild the settings listener provides.
    widget.power.addListener(_rebuildForTheme);
    _previousBrightnessHandler =
        WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged;
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
      _previousBrightnessHandler?.call();
      _rebuildForTheme();
    };
  }

  @override
  void dispose() {
    widget.settings.removeListener(_rebuildForTheme);
    widget.power.removeListener(_rebuildForTheme);
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _previousBrightnessHandler;
    super.dispose();
  }

  TextTheme _themedTextTheme(TextTheme base) {
    final fontKey = widget.settings.get<String>(SettingKey.fontKey);
    return fontKey == 'System' ? base : base.apply(fontFamily: fontKey);
  }

  /// The app theme for these inputs, rebuilt only when one of them changes.
  ThemeData _themeFor({
    required Color accent,
    required Brightness brightness,
    required String fontKey,
    required bool amoled,
  }) {
    final cached = _theme;
    if (cached != null &&
        _themeAccent == accent &&
        _themeBrightness == brightness &&
        _themeFont == fontKey &&
        _themeAmoled == amoled) {
      return cached;
    }

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    ).copyWith(
      surface: FathomColors.background,
      onSurface: FathomColors.onSurface,
      onSurfaceVariant: FathomColors.onSurfaceMuted,
    );

    final theme = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: _themedTextTheme(
        brightness == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      ),
      scaffoldBackgroundColor: FathomColors.background,
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: FathomColors.hairline,
        thickness: 0.5,
      ),
    );

    _theme = theme;
    _themeAccent = accent;
    _themeBrightness = brightness;
    _themeFont = fontKey;
    _themeAmoled = amoled;
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.settings.themeMode;
    final brightness = FathomColors.resolve(mode);
    // Every FathomColors token follows the resolved palette from here, so one
    // assignment repaints the app in the new theme.
    FathomColors.updateBrightness(brightness);
    FathomColors.updateAmoled(widget.settings.get<bool>(SettingKey.amoled));

    GlassContainer.blurEnabled =
        !widget.settings.lowEndInForce(powerSave: widget.power.isPowerSave);

    final overlay = FathomColors.systemUiOverlayStyle();
    if (overlay != _lastOverlay) {
      _lastOverlay = overlay;
      SystemChrome.setSystemUIOverlayStyle(overlay);
    }

    final theme = _themeFor(
      accent: widget.settings.accent,
      brightness: brightness,
      fontKey: widget.settings.get<String>(SettingKey.fontKey),
      amoled: widget.settings.get<bool>(SettingKey.amoled),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: widget.player),
        ChangeNotifierProvider.value(value: widget.library),
        ChangeNotifierProvider.value(value: widget.downloads),
        // Battery Saver is device state, not a preference, so nothing persists
        // it and it is provided here for the one row that has to explain why
        // low-end mode cannot be turned off right now.
        ChangeNotifierProvider.value(value: widget.power),
        // In-memory search state for the rail's single field.
        ChangeNotifierProvider(create: (_) => FathomSearch()),
      ],
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        // One palette, resolved before the theme is built: `themeMode`
        // decides which slot reads it, both slots see the right colors.
        darkTheme: theme,
        theme: theme,
        home: widget.settings.get<bool>(SettingKey.onboarded)
            ? const RootShell()
            : const OnboardingPage(),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = await FathomSettings.load();
  FathomColors.updateBrightness(FathomColors.resolve(settings.themeMode));
  FathomColors.updateAmoled(settings.get<bool>(SettingKey.amoled));
  SystemChrome.setSystemUIOverlayStyle(FathomColors.systemUiOverlayStyle());
  await FathomFonts.instance.loadSaved();

  final player = FathomPlayer(settings);
  final library = FathomLibrary();
  // Publish the last scan before the first frame; the media query then
  // reconciles in the background.
  await library.restoreSnapshot();
  library.load(grantIfMissing: false);
  // The remote source exists for one purpose now: fetching bytes to keep. It
  // is handed to the download service rather than the player, because nothing
  // remote is ever played straight from YouTube.
  final downloads = FathomDownloads(
    source: FathomYtMusic(),
    onFinished: () => library.load(grantIfMissing: false),
  );
  // The one seam between the two records: a fetched file is a device track
  // known by its media id, and its cover was cached under the remote video id
  // the download manifest remembers. The library stays free of the download
  // service; this closure is where the media store and the download record
  // meet, and it runs for every track whose own artwork is missing.
  library.fallbackArtFor = (mediaId) async {
    await downloads.manifestReady;
    final videoId = downloads.videoIdForMediaId(mediaId);
    if (videoId == null) return null;
    return FathomArtCache.instance.cachedForVideo(videoId);
  };
  // Started before the first frame so the boot sync of
  // `GlassContainer.blurEnabled` already sees the device's battery state.
  final power = FathomPowerState();

  runApp(FathomApp(
    settings: settings,
    player: player,
    library: library,
    downloads: downloads,
    power: power,
  ));

  // Restore runs after `initialize`, not beside it: the saved queue is handed
  // to the audio engine and published to audio_service, and doing that before
  // the handler exists would leave the restored session without a media item
  // or a foreground service.
  player
      .initialize()
      .then((_) => player.restoreLastState())
      .catchError((Object e) {
    debugPrint('Fathom boot: $e');
  });

  power.start().catchError((Object e) {
    debugPrint('Fathom boot: $e');
  });
}

/// Everything about a settings/power change that can repaint the app shell.
typedef _Chrome = ({
  Brightness brightness,
  int themeIndex,
  int accentIndex,
  int seedCount,
  bool amoled,
  String fontKey,
  bool lowEnd,
  bool onboarded,
  bool powerSave,
});
