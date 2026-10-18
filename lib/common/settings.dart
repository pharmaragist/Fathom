import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'colors.dart';
import 'constants.dart';

enum SettingKey {
  accentIndex('fathom.accent', 0),
  useArtAccent('fathom.art_accent', false),
  fontKey('fathom.font', 'Oswald'),
  gapless('fathom.gapless', true),
  speedIndex('fathom.speed', 1),
  sortIndex('fathom.sort', 0),
  eqEnabled('fathom.eq.enabled', true),
  eqPreset('fathom.eq.preset', null),
  shuffle('fathom.shuffle', false),
  repeatIndex('fathom.repeat', 0),
  searchQuery('', '');

  const SettingKey(this.prefKey, this.defaultValue);
  final String prefKey;
  final dynamic defaultValue;
}

class FathomSettings extends ChangeNotifier {
  FathomSettings._(
    this._prefs,
    Map<SettingKey, dynamic> initial,
    Map<int, double> gains,
  )   : _values = initial,
        _eqGains = gains;

  final SharedPreferences _prefs;
  final Map<SettingKey, dynamic> _values;
  final Map<int, double> _eqGains;
  Color? _extractedArtAccent;

  static const _kEqGains = 'fathom.eq.gains';

  static Future<FathomSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    final gains = <int, double>{};
    final rawGains = prefs.getString(_kEqGains);
    if (rawGains != null && rawGains.isNotEmpty) {
      for (final part in rawGains.split(',')) {
        final kv = part.split('#');
        if (kv.length == 2) {
          final f = int.tryParse(kv[0]);
          final d = double.tryParse(kv[1]);
          if (f != null && d != null) gains[f] = d;
        }
      }
    }

    final initial = <SettingKey, dynamic>{
      SettingKey.accentIndex: prefs.getInt(SettingKey.accentIndex.prefKey) ?? SettingKey.accentIndex.defaultValue,
      SettingKey.useArtAccent: prefs.getBool(SettingKey.useArtAccent.prefKey) ?? SettingKey.useArtAccent.defaultValue,
      SettingKey.fontKey: prefs.getString(SettingKey.fontKey.prefKey) ?? SettingKey.fontKey.defaultValue,
      SettingKey.gapless: prefs.getBool(SettingKey.gapless.prefKey) ?? SettingKey.gapless.defaultValue,
      SettingKey.speedIndex: prefs.getInt(SettingKey.speedIndex.prefKey) ?? SettingKey.speedIndex.defaultValue,
      SettingKey.sortIndex: prefs.getInt(SettingKey.sortIndex.prefKey) ?? SettingKey.sortIndex.defaultValue,
      SettingKey.eqEnabled: prefs.getBool(SettingKey.eqEnabled.prefKey) ?? SettingKey.eqEnabled.defaultValue,
      SettingKey.eqPreset: prefs.getString(SettingKey.eqPreset.prefKey),
      SettingKey.shuffle: prefs.getBool(SettingKey.shuffle.prefKey) ?? SettingKey.shuffle.defaultValue,
      SettingKey.repeatIndex: prefs.getInt(SettingKey.repeatIndex.prefKey) ?? SettingKey.repeatIndex.defaultValue,
      SettingKey.searchQuery: '',
    };

    return FathomSettings._(prefs, initial, gains);
  }

  T get<T>(SettingKey key) {
    return (_values[key] ?? key.defaultValue) as T;
  }

  void set<T>(SettingKey key, T value) {
    if (_values[key] == value) return;

    _values[key] = value;

    if (key.prefKey.isNotEmpty) {
      if (value is int) {
        _prefs.setInt(key.prefKey, value);
      } else if (value is bool) {
        _prefs.setBool(key.prefKey, value);
      } else if (value is String) {
        _prefs.setString(key.prefKey, value);
      } else if (value == null) {
        _prefs.remove(key.prefKey);
      }
    }

    notifyListeners();
  }

  Color get accent {
    final useArt = get<bool>(SettingKey.useArtAccent);
    if (useArt && _extractedArtAccent != null) return _extractedArtAccent!;
    final index = get<int>(SettingKey.accentIndex).clamp(0, FathomColors.accentSwatches.length - 1);
    return FathomColors.accentSwatches[index];
  }

  FathomRepeatMode get repeatMode {
    final index = get<int>(SettingKey.repeatIndex).clamp(0, FathomRepeatMode.values.length - 1);
    return FathomRepeatMode.values[index];
  }

  Map<int, double> get eqGains => Map.unmodifiable(_eqGains);

  void updateArtAccent(Color? color) {
    if (_extractedArtAccent == color) return;
    _extractedArtAccent = color;
    if (get<bool>(SettingKey.useArtAccent)) notifyListeners();
  }

  void stageEqGain(int centerHz, double db) => _eqGains[centerHz] = db;

  void commitEq() {
    final encoded = _eqGains.entries
        .map((e) => '${e.key}#${e.value.toStringAsFixed(2)}')
        .join(',');
    _prefs.setString(_kEqGains, encoded);
  }
}
