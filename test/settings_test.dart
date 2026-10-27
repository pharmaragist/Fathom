import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'package:fathom/common/colors.dart';
import 'package:fathom/common/library.dart';
import 'package:fathom/common/settings.dart';
import 'package:fathom/components/flat_switch.dart';
import 'package:fathom/pages/settings.dart';
import 'package:fathom/services/power.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings load with documented defaults on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await FathomSettings.load();

    expect(settings.get<bool>(SettingKey.dataSave), isFalse);
    expect(settings.get<bool>(SettingKey.gapless), isTrue);
    expect(settings.get<bool>(SettingKey.eqEnabled), isTrue);
    expect(settings.get<bool>(SettingKey.limiter), isTrue);
    expect(settings.get<int>(SettingKey.sortIndex), 0);
    expect(settings.get<bool>(SettingKey.amoled), isFalse);
    expect(settings.get<bool>(SettingKey.onboarded), isFalse);
    expect(FathomColors.accentSwatches.length, 4);
  });

  test('the AMOLED choice persists across loads', () async {
    SharedPreferences.setMockInitialValues({});

    final first = await FathomSettings.load();
    first.set(SettingKey.amoled, true);

    final second = await FathomSettings.load();
    expect(second.get<bool>(SettingKey.amoled), isTrue);
  });

  test('a custom accent seed persists across loads', () async {
    SharedPreferences.setMockInitialValues({});
    const seed = Color(0xFF2F6F4E);

    final first = await FathomSettings.load();
    expect(first.accentSeeds.length, FathomColors.accentSwatches.length);
    expect(first.addAccentSeed(seed), isTrue);
    expect(first.accentSeeds.last, seed);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('fathom.accent.custom')!) as List;
    expect(stored, [seed.toARGB32()]);

    final second = await FathomSettings.load();
    expect(second.accentSeeds.first, FathomColors.accentSwatches.first);
    expect(second.accentSeeds.last, seed);
  });

  test('selecting a custom accent seed is what settings.accent returns',
      () async {
    SharedPreferences.setMockInitialValues({});
    const seed = Color(0xFF2F6F4E);

    final first = await FathomSettings.load();
    expect(first.addAccentSeed(seed), isTrue);

    // Customs follow the built-ins, so the new seed is the last index. The
    // stored seed stays raw; `accent` is the readability-clamped color the app
    // actually paints, so a dark seed is lifted in the dark theme.
    final index = first.accentSeeds.indexOf(seed);
    expect(index, FathomColors.accentSwatches.length);
    first.set(SettingKey.accentIndex, index);
    expect(first.accent, FathomColors.readableAccent(seed));

    // The index survives a restart against the reloaded combined list.
    final second = await FathomSettings.load();
    expect(second.get<int>(SettingKey.accentIndex), index);
    expect(second.accent, FathomColors.readableAccent(seed));
  });

  test('adding a duplicate accent seed does not grow the list', () async {
    SharedPreferences.setMockInitialValues({});
    const seed = Color(0xFF2F6F4E);

    final settings = await FathomSettings.load();
    final builtInCount = FathomColors.accentSwatches.length;
    expect(settings.accentSeeds.length, builtInCount);

    // A built-in seed is a duplicate too.
    expect(settings.addAccentSeed(FathomColors.accentSwatches[1]), isFalse);
    expect(settings.accentSeeds.length, builtInCount);

    expect(settings.addAccentSeed(seed), isTrue);
    expect(settings.accentSeeds.length, builtInCount + 1);

    expect(settings.addAccentSeed(seed), isFalse);
    expect(settings.accentSeeds.length, builtInCount + 1);
    expect(FathomColors.accentSwatches.length, builtInCount);
  });

  test('set writes through to the store and reports a real change', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await FathomSettings.load();
    var notifications = 0;
    settings.addListener(() => notifications++);

    settings.set(SettingKey.dataSave, true);
    expect(settings.get<bool>(SettingKey.dataSave), isTrue);
    expect(notifications, 1);

    // Writing the same value again must not notify.
    settings.set(SettingKey.dataSave, true);
    expect(notifications, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fathom.data_save'), isTrue);
  });

  /// Mounts the real settings page over the provided store; the library and
  /// power notifiers are inert instances, which is all the page reads.
  Widget settingsHarness(FathomSettings settings, {FathomPowerState? power}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FathomSettings>.value(value: settings),
        ChangeNotifierProvider<FathomLibrary>.value(value: FathomLibrary()),
        ChangeNotifierProvider<FathomPowerState>.value(
            value: power ?? FathomPowerState()),
      ],
      child: MaterialApp(home: Material(child: SettingsPage())),
    );
  }

  testWidgets(
      'the gapless row toggles once per tap, on the switch or the label',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await FathomSettings.load();
    var notifications = 0;
    settings.addListener(() => notifications++);

    await tester.pumpWidget(settingsHarness(settings));
    await tester.pumpAndSettle();

    final row = find
        .ancestor(
          of: find.text('Gapless playback'),
          matching: find.byType(InkWell),
        )
        .first;
    final toggle = find.descendant(of: row, matching: find.byType(FlatSwitch));

    // One tap on the switch itself: the row's handler runs exactly once, so
    // the value flips and the store notifies a real change once.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(settings.get<bool>(SettingKey.gapless), isFalse);
    expect(notifications, 1);

    // One tap on the label: fires once again, flipping the value back.
    await tester.tap(find.text('Gapless playback'));
    await tester.pumpAndSettle();
    expect(settings.get<bool>(SettingKey.gapless), isTrue);
    expect(notifications, 2);
  });

  testWidgets('the accent sheet adds a custom seed and refuses a duplicate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await FathomSettings.load();

    await tester.pumpWidget(settingsHarness(settings));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Accent color'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accent color'));
    await tester.pumpAndSettle();

    // The add tile follows the built-in swatches in the sheet's wrap.
    await tester.tap(find.byIcon(TablerIcons.plus));
    await tester.pumpAndSettle();
    expect(find.text('Custom accent'), findsOneWidget);

    // A color already in the list is refused in place: the dialog stays open
    // and the stored list does not grow.
    final count = settings.accentSeeds.length;
    await tester.enterText(find.byType(TextField), '#FFFFFF');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Custom accent'), findsOneWidget);
    expect(
        find.text('That seed is already in the accent list.'), findsOneWidget);
    expect(settings.accentSeeds.length, count);

    // A new hex value is stored, selected, and the sheet beneath stays open.
    await tester.enterText(find.byType(TextField), '#123456');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Custom accent'), findsNothing);
    expect(settings.accentSeeds.length, count + 1);
    expect(
        settings.accent, FathomColors.readableAccent(const Color(0xFF123456)));
    expect(settings.get<int>(SettingKey.accentIndex), count);
  });

  testWidgets('the locked low-end row does not fire from switch or label',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await FathomSettings.load();
    const powerChannel = MethodChannel('pharmaracist.fathom/power');
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(powerChannel, (call) async {
      return call.method == 'isPowerSave' ? true : null;
    });
    addTearDown(() => TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(powerChannel, null));

    final power = FathomPowerState();
    await power.start();

    var notifications = 0;
    settings.addListener(() => notifications++);

    await tester.pumpWidget(settingsHarness(settings, power: power));
    await tester.pumpAndSettle();

    // The row sits at the bottom of the page, below the default test
    // viewport, so the taps must be brought to it by scrolling first.
    await tester.scrollUntilVisible(
      find.text('Low-end mode'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Power save keeps the row on screen, showing the device state with its
    // reason underneath, but the row must not toggle from anywhere on it.
    expect(find.text('On: battery saver'), findsOneWidget);
    final row = find
        .ancestor(
          of: find.text('Low-end mode'),
          matching: find.byType(InkWell),
        )
        .first;

    await tester
        .tap(find.descendant(of: row, matching: find.byType(FlatSwitch)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low-end mode'));
    await tester.pumpAndSettle();

    expect(settings.get<bool>(SettingKey.lowEnd), isFalse);
    expect(notifications, 0);
  });
}
