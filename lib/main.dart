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
import 'common/toasts.dart';
import 'components/glass.dart';
import 'content.dart';
import 'services/downloads.dart';
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

  /// The theme mode and the palette both hang off these two sources, so the
  /// whole subtree has to rebuild when either changes.
  void _rebuildForTheme() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
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
    return fontKey == 'Oswald' ? base.apply(fontFamily: 'Oswald') : base;
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.settings.themeMode;
    final brightness = FathomColors.resolve(mode);
    // Every FathomColors token follows the resolved palette from here, so
    // one assignment repaints the app in the new theme.
    FathomColors.updateBrightness(brightness);

    // Glass blur is a global: `GlassContainer` reads it while building, so
    // turning it off only takes effect when the subtree is rebuilt. A setting
    // change already rebuilds this widget (see `_rebuildForTheme`), and so does
    // a power save change, so the sync belongs here, next to the palette. The
    // value is the *effective* one: `lowEndInForce` adds the device's battery
    // state on top of the stored preference without ever writing it back.
    GlassContainer.blurEnabled =
        !widget.settings.lowEndInForce(powerSave: widget.power.isPowerSave);

    final overlay = FathomColors.systemUiOverlayStyle();
    if (overlay != _lastOverlay) {
      _lastOverlay = overlay;
      SystemChrome.setSystemUIOverlayStyle(overlay);
    }

    final scheme = ColorScheme.fromSeed(
      seedColor: widget.settings.accent,
      brightness: brightness,
    ).copyWith(
      surface: FathomColors.background,
      onSurface: FathomColors.onSurface,
      onSurfaceVariant: FathomColors.onSurfaceMuted,
    );

    final textTheme = _themedTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );

    final theme = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: textTheme,
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
        // The shell's toast queue. Created here rather than in the shell so a
        // message raised just before a page switch is not lost with the page
        // that raised it.
        ChangeNotifierProvider(create: (_) => FathomToasts()),
      ],
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        // One palette, resolved before the theme is built: `themeMode`
        // decides which slot reads it, both slots see the right colors.
        darkTheme: theme,
        theme: theme,
        home: const RootShell(),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = await FathomSettings.load();
  FathomColors.updateBrightness(FathomColors.resolve(settings.themeMode));
  SystemChrome.setSystemUIOverlayStyle(FathomColors.systemUiOverlayStyle());

  final player = FathomPlayer(settings);
  final library = FathomLibrary()..load(grantIfMissing: false);
  // The remote source exists for one purpose now: fetching bytes to keep. It
  // is handed to the download service rather than the player, because nothing
  // remote is ever played straight from YouTube.
  final downloads = FathomDownloads(
    source: FathomYtMusic(),
    onFinished: () => library.load(grantIfMissing: false),
  );
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

  power.start().catchError((Object e) {
    debugPrint('Fathom boot: $e');
  });

  player.initialize().catchError((Object e) {
    debugPrint('Fathom boot: $e');
  });
}
