import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'colors.dart';
import 'constants.dart';

enum SettingKey {
  accentIndex('fathom.accent', 0),
  fontKey('fathom.font', 'Oswald'),
  // 0 light, 1 dark, 2 follow the device.
  themeIndex('fathom.theme', 2),
  // Pure black behind the dark theme.
  amoled('fathom.amoled', false),
  // False until the first-run walkthrough is finished.
  onboarded('fathom.onboarded', false),
  gapless('fathom.gapless', true),
  speedIndex('fathom.speed', 1),
  sortIndex('fathom.sort', 0),
  eqEnabled('fathom.eq.enabled', true),
  eqPreset('fathom.eq.preset', null),
  // Soft peak limiter after preamp and EQ, on by default. A safety net against
  // clipping from boosts, never a loudness normalizer.
  limiter('fathom.eq.limiter', true),
  shuffle('fathom.shuffle', false),
  repeatIndex('fathom.repeat', 0),
  // Cheaper remote requests: smaller thumbnails, fewer rows and results.
  dataSave('fathom.data_save', false),
  // Drops the frosted-glass blur for flat fills: cheaper to composite on
  // weak GPUs, at the cost of the glass look.
  lowEnd('fathom.low_end', false);

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
    this._customAccentSeeds,
  )   : _values = initial,
        _eqGains = gains;

  final SharedPreferences _prefs;
  final Map<SettingKey, dynamic> _values;
  final Map<int, double> _eqGains;
  double _eqPreamp;
  final Map<String, EqPreset> _eqPresets;

  /// User-added accent seeds, in the order they were added.
  ///
  /// Out-of-band like the EQ presets: the pref holds an encoded list, not a
  /// [SettingKey] value, because this is data the user owns rather than a
  /// single choice. [accentSeeds] is the combined view every surface reads.
  final List<Color> _customAccentSeeds;

  /// Cached combined view; dropped whenever [_customAccentSeeds] changes.
  List<Color>? _accentSeeds;

  static const _kEqGains = 'fathom.eq.gains';
  static const _kEqPreamp = 'fathom.eq.preamp';
  static const _kEqPresets = 'fathom.eq.presets';
  static const _kAccentSeeds = 'fathom.accent.custom';

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

    final customSeeds = <Color>[];
    final rawSeeds = prefs.getString(_kAccentSeeds);
    if (rawSeeds != null && rawSeeds.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSeeds);
        if (decoded is List) {
          for (final value in decoded) {
            if (value is! int) continue;
            // Seeds are always opaque, so a malformed legacy value can never
            // restore an invisible swatch.
            final seed = Color(0xFF000000 | (value & 0xFFFFFF));
            if (!customSeeds.contains(seed)) customSeeds.add(seed);
          }
        }
      } catch (_) {}
    }

    final initial = <SettingKey, dynamic>{
      for (final key in SettingKey.values)
        key: switch (key.defaultValue) {
          final int fallback => prefs.getInt(key.prefKey) ?? fallback,
          final bool fallback => prefs.getBool(key.prefKey) ?? fallback,
          final String fallback => prefs.getString(key.prefKey) ?? fallback,
          _ => prefs.get(key.prefKey),
        },
    };

    return FathomSettings._(
      prefs,
      initial,
      gains,
      prefs.getDouble(_kEqPreamp) ?? 0.0,
      presets,
      customSeeds,
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

  /// Every accent seed the user can pick: the built-ins from
  /// [FathomColors.accentSwatches] followed by the custom seeds, in the order
  /// they were added.
  ///
  /// This is the list [SettingKey.accentIndex] indexes, and the only list a
  /// swatch surface renders. The built-in constant is never mutated, so a
  /// session's custom seeds cannot leak into it. The view is unmodifiable and
  /// is rebuilt only when [addAccentSeed] appends, which keeps the order
  /// stable for an index stored in an earlier session.
  List<Color> get accentSeeds => _accentSeeds ??= List.unmodifiable([
        ...FathomColors.accentSwatches,
        ..._customAccentSeeds,
      ]);

  /// Appends [color] as a selectable accent seed and returns whether it landed.
  ///
  /// A color already in [accentSeeds] — built-in or custom — is refused so
  /// the picker can say why instead of adding a second identical swatch. A
  /// successful add is persisted immediately (a JSON list of ARGB ints under
  /// `fathom.accent.custom`) and notifies, so every swatch surface grows the
  /// new choice. Selecting it is the caller's next step, through
  /// [SettingKey.accentIndex] on the returned combined list.
  bool addAccentSeed(Color color) {
    final seed = Color(0xFF000000 | (color.toARGB32() & 0xFFFFFF));
    if (accentSeeds.contains(seed)) return false;

    _customAccentSeeds.add(seed);
    _accentSeeds = null;
    _prefs.setString(
      _kAccentSeeds,
      jsonEncode([
        for (final custom in _customAccentSeeds) custom.toARGB32(),
      ]),
    );
    notifyListeners();
    return true;
  }

  /// The accent every surface paints with.
  ///
  /// The stored or extracted color is passed through
  /// [FathomColors.readableAccent] before it leaves this getter, so a dark seed
  /// in the dark theme and a pale seed in the light theme cannot vanish into
  /// the background. The clamp keeps the seed's hue and chroma; it only moves
  /// its tone. [accentSeeds] still returns the raw choices, because that list
  /// is what the picker renders and what [SettingKey.accentIndex] indexes.
  Color get accent {
    final seeds = accentSeeds;
    final raw =
        seeds[get<int>(SettingKey.accentIndex).clamp(0, seeds.length - 1)];
    return FathomColors.readableAccent(raw);
  }

  /// The stored theme choice resolved to a [ThemeMode].
  ThemeMode get themeMode =>
      switch (get<int>(SettingKey.themeIndex).clamp(0, 2)) {
        0 => ThemeMode.light,
        1 => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  FathomRepeatMode get repeatMode {
    final index = get<int>(SettingKey.repeatIndex)
        .clamp(0, FathomRepeatMode.values.length - 1);
    return FathomRepeatMode.values[index];
  }

  /// Whether low-end rendering is actually in force right now.
  ///
  /// This is [SettingKey.lowEnd] or `powerSave`: Android's Battery Saver forces
  /// the mode on, and the user cannot turn it off while it is active. The stored
  /// key is never written to from here, so switching power save off restores
  /// exactly what the user chose; the override lives only in this read.
  ///
  /// The state is a parameter rather than a dependency on the native power
  /// service, because `FathomSettings` is a preference store and the device's
  /// battery state is not a preference. Every caller has the power state in
  /// hand already — `FathomApp.build` from its notifier, the settings row from
  /// `select` — so passing it in keeps this a pure mapping and keeps the one
  /// answer to "is low-end in force" in a single place.
  bool lowEndInForce({required bool powerSave}) =>
      powerSave || get<bool>(SettingKey.lowEnd);

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

    if (replacing == null ||
        replacing == name ||
        !_eqPresets.containsKey(replacing)) {
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
