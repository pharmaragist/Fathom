import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'common/colors.dart';
import 'common/constants.dart';
import 'common/library.dart';
import 'common/player.dart';
import 'common/settings.dart';
import 'content.dart';

class FathomApp extends StatelessWidget {
  const FathomApp({super.key, required this.settings, required this.player});

  final FathomSettings settings;
  final FathomPlayer player;

  TextTheme _themedTextTheme(TextTheme base) {
    final fontKey = settings.get<String>(SettingKey.fontKey);
    return fontKey == 'Oswald' ? base.apply(fontFamily: 'Oswald') : base;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: settings.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: FathomColors.surface,
      onSurface: FathomColors.onSurface,
      onSurfaceVariant: FathomColors.onSurfaceMuted,
    );

    final textTheme = _themedTextTheme(ThemeData.dark().textTheme);

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
        color: Colors.white.withValues(alpha: 0.10),
        thickness: 0.5,
      ),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider(
          create: (_) => FathomLibrary()..load(grantIfMissing: false),
        ),
      ],
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
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
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: FathomColors.background,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final settings = await FathomSettings.load();
  final player = FathomPlayer(settings);

  runApp(FathomApp(settings: settings, player: player));

  player.initialize().catchError((Object e) {
    debugPrint('Fathom boot: $e');
  });
}
