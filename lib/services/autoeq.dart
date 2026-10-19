import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../common/constants.dart';
import 'equalizer.dart';

/// Failure raised while talking to the AutoEQ catalogue.
class AutoEqException implements Exception {
  const AutoEqException(this.message);

  /// Human readable reason, safe to show in the UI.
  final String message;

  @override
  String toString() => message;
}

/// One recommended AutoEQ result.
class AutoEqEntry {
  const AutoEqEntry({required this.name, required this.path});

  /// Headphone name as published in the index.
  final String name;

  /// Percent-encoded result directory, relative to `results/`.
  final String path;

  /// Measurement source and form, e.g. `oratory1990 · over-ear`.
  String get origin {
    final parts = Uri.decodeFull(path).split('/');
    return parts.length >= 2 ? '${parts[0]} · ${parts[1]}' : path;
  }
}

/// A fetched AutoEQ result, ready to be stored as a Fathom preset.
class AutoEqPreset {
  const AutoEqPreset({required this.name, required this.preset});

  /// Preset name to store the curve under.
  final String name;

  /// Ten band curve plus the headroom the catalogue recommends.
  final EqPreset preset;
}

/// Read-only client for the public AutoEQ catalogue
/// (github.com/jaakkopasanen/AutoEq).
///
/// Every recommended result publishes a ten band correction as
/// `<results>/<source>/<form>/<model>/<model> FixedBandEQ.txt` whose bands line
/// up with [kEq10Bands], so an import maps onto the Fathom equalizer without
/// resampling. The index is fetched once per process and cached in memory.
class FathomAutoEq {
  FathomAutoEq._() {
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  /// Process-wide client, so the index is downloaded at most once.
  static final FathomAutoEq instance = FathomAutoEq._();

  static const String _indexUrl =
      'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/README.md';
  static const String _resultsBase =
      'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/';

  static final RegExp _indexLink =
      RegExp(r'^-\s+\[(.+?)\]\(\./(.+?)\)\s*$', multiLine: true);
  static final RegExp _filterLine = RegExp(
    r'Filter \d+:\s+\w+\s+\w+\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB',
  );
  static final RegExp _preampLine =
      RegExp(r'Preamp:\s*(-?[\d.]+)\s*dB', multiLine: true);

  final HttpClient _client = HttpClient();

  List<AutoEqEntry>? _index;
  Future<List<AutoEqEntry>>? _pending;

  /// The recommended results, in published order.
  Future<List<AutoEqEntry>> entries() {
    final cached = _index;
    if (cached != null) return Future<List<AutoEqEntry>>.value(cached);
    return _pending ??= _fetchIndex().then((list) {
      _index = list;
      return list;
    }).whenComplete(() => _pending = null);
  }

  /// Downloads the curve described by [entry].
  Future<EqPreset> fetch(AutoEqEntry entry) async {
    final model = entry.path.split('/').last;
    final body = await _get('$_resultsBase${entry.path}/$model%20FixedBandEQ.txt');
    final preset = _parseFixedBand(body);
    if (preset == null) {
      throw const AutoEqException(
        'That result has no ten band correction Fathom can use.',
      );
    }
    return preset;
  }

  Future<List<AutoEqEntry>> _fetchIndex() async {
    final body = await _get(_indexUrl);

    final entries = <AutoEqEntry>[];
    final seen = <String>{};
    for (final match in _indexLink.allMatches(body)) {
      final name = match.group(1)!.trim();
      final path = match.group(2)!.trim();
      if (name.isEmpty || path.isEmpty || !seen.add(path)) continue;
      entries.add(AutoEqEntry(name: name, path: path));
    }

    if (entries.isEmpty) {
      throw const AutoEqException('The AutoEQ index came back empty.');
    }
    return entries;
  }

  /// Parses a `FixedBandEQ.txt` document.
  ///
  /// Returns null unless the document carries exactly [kEq10Bands] filters in
  /// the expected order, so a mismatched curve is never applied. Gains are held
  /// inside the native range; when the document omits its own preamp the peak
  /// gain is cancelled so boosted bands cannot clip.
  static EqPreset? _parseFixedBand(String body) {
    final gains = <double>[];
    for (final match in _filterLine.allMatches(body)) {
      if (gains.length >= kEq10Bands.length) return null;

      final fc = double.tryParse(match.group(1)!);
      final gain = double.tryParse(match.group(2)!);
      if (fc == null || gain == null) return null;

      // The published bands sit within a few percent of the Fathom bands.
      if ((fc - kEq10Bands[gains.length]).abs() > kEq10Bands[gains.length] * 0.1) {
        return null;
      }
      gains.add(
        gain
            .clamp(
              FathomNativeEqualizer.minDecibels,
              FathomNativeEqualizer.maxDecibels,
            )
            .toDouble(),
      );
    }

    if (gains.length != kEq10Bands.length) return null;

    final line = _preampLine.firstMatch(body);
    final stored = line == null ? null : double.tryParse(line.group(1)!);
    final peak = gains.fold(0.0, (high, gain) => gain > high ? gain : high);

    return EqPreset(
      gains: gains,
      preamp: (stored ?? (peak > 0 ? -peak : 0.0))
          .clamp(
            -FathomNativeEqualizer.maxPreampDecibels,
            FathomNativeEqualizer.maxPreampDecibels,
          )
          .toDouble(),
      source: EqPresetSource.autoEq,
    );
  }

  Future<String> _get(String url) async {
    try {
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AutoEqException('AutoEQ responded with ${response.statusCode}.');
      }
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
    } on AutoEqException {
      rethrow;
    } catch (e) {
      throw const AutoEqException(
        'Could not reach AutoEQ. Check the connection and try again.',
      );
    }
  }
}
