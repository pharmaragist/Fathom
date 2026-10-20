import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fathom/common/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings load with documented defaults on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await FathomSettings.load();

    expect(settings.get<bool>(SettingKey.dataSave), isFalse);
    expect(settings.get<bool>(SettingKey.gapless), isTrue);
    expect(settings.get<bool>(SettingKey.eqEnabled), isTrue);
    expect(settings.get<int>(SettingKey.sortIndex), 0);
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
}
