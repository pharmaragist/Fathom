import 'dart:convert';

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
  repeatIndex('fathom.repeat', 0);


  const SettingKey(this.prefKey, this.defaultValue);
  final String prefKey;
  final dynamic defaultValue;
}

class FathomSettings extends ChangeNotifier {
  FathomSettings._(
    this._prefs,
    Map<SettingKey, dynamic> initial,
    Map<int, double> gains,
    this._eqPreamp,
    this._eqPresets,
  )   : _values = initial,
        _eqGains = gains;

  final SharedPreferences _prefs;
  final Map<SettingKey, dynamic> _values;
  final Map<int, double> _eqGains;
  double _eqPreamp;
  final Map<String, EqPreset> _eqPresets;
  Color? _extractedArtAccent;

  static const _kEqGains = 'fathom.eq.gains';
  static const _kEqPreamp = 'fathom.eq.preamp';
  static const _kEqPresets = 'fathom.eq.presets';

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

    final presets = <String, EqPreset>{};
    final rawPresets = prefs.getString(_kEqPresets);
    if (rawPresets != null && rawPresets.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPresets);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final name = entry.key;
            if (name is! String || name.isEmpty) continue;
            // Built-in names always win, so never load a shadowing entry.
            if (kBuiltInEqPresets.containsKey(name)) continue;
            final preset = EqPreset.fromJson(entry.value);
            if (preset != null) presets[name] = preset;
          }
        }
      } catch (_) {}
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
    };

    return FathomSettings._(
      prefs,
      initial,
      gains,
      prefs.getDouble(_kEqPreamp) ?? 0.0,
      presets,
    );
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

  /// Every named equalizer curve keyed by name, in insertion order.
  ///
  /// Stored curves only; built-ins come from [kBuiltInEqPresets].
  Map<String, EqPreset> get eqPresets => Map.unmodifiable(_eqPresets);

  /// The curve called [name], built-in or stored, or null when unknown.
  ///
  /// This is the single lookup for every preset consumer. Built-ins are
  /// resolved first and their names are reserved, so nothing shadows them.
  EqPreset? eqPresetFor(String? name) {
    if (name == null) return null;
    return kBuiltInEqPresets[name] ?? _eqPresets[name];
  }

  /// The stored preset names owned by [source], in insertion order.
  List<String> eqPresetNames(EqPresetSource source) => [
        for (final entry in _eqPresets.entries)
          if (entry.value.source == source) entry.key,
      ];

  /// Global output trim in decibels applied before the band filters.
  double get eqPreamp => _eqPreamp;

  void updateArtAccent(Color? color) {
    if (_extractedArtAccent == color) return;
    _extractedArtAccent = color;
    if (get<bool>(SettingKey.useArtAccent)) notifyListeners();
  }

  void stageEqGain(int centerHz, double db) => _eqGains[centerHz] = db;

  void stageEqPreamp(double db) => _eqPreamp = db;

  void commitEq() {
    final encoded = _eqGains.entries
        .map((e) => '${e.key}#${e.value.toStringAsFixed(2)}')
        .join(',');
    _prefs.setString(_kEqGains, encoded);
    _prefs.setDouble(_kEqPreamp, _eqPreamp);
  }

  /// Stores [preset] under [name].
  ///
  /// Names used by [kBuiltInEqPresets] are reserved and ignored here; the
  /// preset sheet blocks them, this is the backstop. When [replacing] names a
  /// different existing entry the entry is renamed in place instead of leaving
  /// a duplicate behind.
  void saveEqPreset(String name, EqPreset preset, {String? replacing}) {
    if (kBuiltInEqPresets.containsKey(name)) return;

    if (replacing == null || replacing == name || !_eqPresets.containsKey(replacing)) {
      _eqPresets[name] = preset;
    } else {
      final rebuilt = <String, EqPreset>{};
      for (final entry in _eqPresets.entries) {
        if (entry.key == replacing) {
          rebuilt[name] = preset;
        } else {
          rebuilt[entry.key] = entry.value;
        }
      }
      _eqPresets
        ..clear()
        ..addAll(rebuilt);
    }

    _persistEqPresets();
    notifyListeners();
  }

  void removeEqPreset(String name) {
    if (kBuiltInEqPresets.containsKey(name)) return;
    if (_eqPresets.remove(name) == null) return;
    _persistEqPresets();
    notifyListeners();
  }

  void _persistEqPresets() {
    _prefs.setString(
      _kEqPresets,
      jsonEncode({
        for (final entry in _eqPresets.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
