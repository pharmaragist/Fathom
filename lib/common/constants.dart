const String kAppName = 'Fathom';
const String kAppCreator = 'pharmaracist';
const String kAppSubtitle = 'by $kAppCreator';
const String kAppVersion = '1.0.0';

const double kBottomNavWidth = 305.0;
const List<String> kFontOptions = ['System', 'Oswald'];

const List<double> kSpeedFactors = [0.5, 1.0, 1.25, 1.5, 2.0];
const List<String> kSpeedLabels = ['0.5x', '1x', '1.25x', '1.5x', '2x'];

const List<int> kEq10Bands = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const List<String> kEqPresets = [
  'Flat',
  'Bass Boost',
  'Vocal Boost',
  'Rock',
  'Electronic'
];

const Map<String, List<double>> kEqPresetGains10 = {
  'Flat': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  'Bass Boost': [7.0, 6.0, 5.0, 3.0, 1.0, 0.0, -1.0, -1.5, -2.0, -2.0],
  'Vocal Boost': [-1.0, -0.5, 0.0, 1.5, 3.0, 3.5, 2.5, 1.0, 0.0, -1.0],
  'Rock': [5.0, 4.0, 3.0, 1.5, -0.5, -0.5, 1.0, 2.5, 3.5, 4.5],
  'Electronic': [6.0, 5.5, 4.0, 2.0, 0.0, -1.0, 0.5, 2.0, 3.5, 4.0],
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
