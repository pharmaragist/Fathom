const String kAppName = 'Fathom';

const List<String> kFontOptions = ['System', 'Oswald'];

const List<double> kSpeedFactors = [0.5, 1.0, 1.25, 1.5, 2.0];
const List<String> kSpeedLabels = ['0.5x', '1x', '1.25x', '1.5x', '2x'];

const List<int> kEq10Bands = [
  31,
  63,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000
];

/// Where a named equalizer curve came from.
enum EqPresetSource {
  /// Shipped with Fathom. Built-in names are reserved and never persisted.
  builtIn('builtin'),

  /// Saved from the equalizer page.
  user('user'),

  /// Imported from an AutoEQ measurement set.
  autoEq('autoeq');

  const EqPresetSource(this.wireName);

  /// Stable identifier used in persisted JSON.
  final String wireName;

  /// Parses [raw], falling back to [EqPresetSource.user] when unrecognised.
  static EqPresetSource fromWire(Object? raw) {
    for (final source in values) {
      if (source.wireName == raw) return source;
    }
    return EqPresetSource.user;
  }
}

/// A named equalizer curve: ten band gains plus the preamp that feeds them.
///
/// Built-in, saved and imported curves all share this shape, so one lookup and
/// one apply path covers every preset.
class EqPreset {
  const EqPreset({
    required this.gains,
    required this.preamp,
    this.source = EqPresetSource.user,
  });

  /// Ten band gains in [kEq10Bands] order, in decibels.
  final List<double> gains;

  /// Input gain applied before the band filters, in decibels.
  final double preamp;

  /// Where the curve came from.
  final EqPresetSource source;

  Map<String, dynamic> toJson() => {
        'gains': gains,
        'preamp': preamp,
        'source': source.wireName,
      };

  /// Parses a persisted preset, returning null when the payload is unusable.
  static EqPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final rawGains = raw['gains'];
    if (rawGains is! List || rawGains.length != kEq10Bands.length) return null;

    final gains = <double>[];
    for (final gain in rawGains) {
      if (gain is! num) return null;
      gains.add(gain.toDouble());
    }

    final preamp = raw['preamp'];
    return EqPreset(
      gains: gains,
      preamp: preamp is num ? preamp.toDouble() : 0.0,
      source: EqPresetSource.fromWire(raw['source']),
    );
  }
}

/// The curves Fathom ships with, keyed by name.
///
/// Each preamp cancels its own peak so an applied curve cannot clip. These are
/// never persisted: `FathomSettings.eqPresetFor` resolves them exactly like a
/// stored preset, and their names are reserved.
const Map<String, EqPreset> kBuiltInEqPresets = {
  'Bass Boost': EqPreset(
    gains: [7.0, 6.0, 5.0, 3.0, 1.0, 0.0, -1.0, -1.5, -2.0, -2.0],
    preamp: -7.0,
    source: EqPresetSource.builtIn,
  ),
  'Vocal Boost': EqPreset(
    gains: [-1.0, -0.5, 0.0, 1.5, 3.0, 3.5, 2.5, 1.0, 0.0, -1.0],
    preamp: -3.5,
    source: EqPresetSource.builtIn,
  ),
  'Rock': EqPreset(
    gains: [5.0, 4.0, 3.0, 1.5, -0.5, -0.5, 1.0, 2.5, 3.5, 4.5],
    preamp: -5.0,
    source: EqPresetSource.builtIn,
  ),
};

String formatDuration(Duration d) {
  final min = d.inMinutes;
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$min:$sec';
}

String frequencyLabel(int hz) {
  if (hz >= 1000) {
    final k = hz / 1000.0;
    return k == k.roundToDouble()
        ? '${k.toInt()}k'
        : '${k.toStringAsFixed(1)}k';
  }
  return '$hz';
}

enum FathomRepeatMode { off, all, one }
