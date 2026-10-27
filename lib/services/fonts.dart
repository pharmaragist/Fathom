import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// One family in the Google Fonts catalogue.
class FathomFontFamily {
  const FathomFontFamily({
    required this.family,
    required this.category,
    required this.popularity,
  });

  final String family;
  final String category;
  final int popularity;
}

/// Downloads and registers Google Fonts at runtime.
///
/// Fonts are stored as TTF files in the app's support directory and loaded with
/// a [FontLoader]. Nothing is bundled, so the list can grow without an app
/// update; a font is fetched only when the user installs it.
class FathomFonts {
  FathomFonts._();

  static final FathomFonts instance = FathomFonts._();

  static const _metadataUrl = 'https://fonts.google.com/metadata/fonts';
  static const _cssUrl = 'https://fonts.googleapis.com/css2';

  final List<String> _installed = [];
  List<FathomFontFamily>? _catalogue;
  Future<List<FathomFontFamily>>? _loading;

  /// Families already registered with the engine, built-ins excluded.
  List<String> get installed => List.unmodifiable(_installed);

  Directory? _directory;
  Future<Directory> _fontDirectory() async {
    final cached = _directory;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/fonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _directory = dir;
  }

  static String _fileName(String family) =>
      '${family.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_')}.ttf';

  static ByteData _data(Uint8List bytes) => ByteData.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  /// Loads every font installed in an earlier session.
  Future<void> loadSaved() async {
    try {
      final dir = await _fontDirectory();
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.ttf')) continue;
        final name = entity.uri.pathSegments.last;
        final family = name.substring(0, name.length - 4);
        try {
          final bytes = await entity.readAsBytes();
          final loader = FontLoader(family)
            ..addFont(Future.value(_data(bytes)));
          await loader.load();
          if (!_installed.contains(family)) _installed.add(family);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// The full Google Fonts catalogue, fetched once per process.
  Future<List<FathomFontFamily>> catalogue() {
    final cached = _catalogue;
    if (cached != null) return Future.value(cached);
    return _loading ??= _fetchCatalogue().then((list) {
      _catalogue = list;
      return list;
    }).whenComplete(() => _loading = null);
  }

  Future<List<FathomFontFamily>> _fetchCatalogue() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(_metadataUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Font catalogue said ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final start = body.indexOf('{');
      if (start < 0) throw const FormatException('Font catalogue was empty');

      final decoded = jsonDecode(body.substring(start));
      final raw = decoded is Map ? decoded['familyMetadataList'] : null;
      if (raw is! List) {
        throw const FormatException('Font catalogue was invalid');
      }

      final families = <FathomFontFamily>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final family = entry['family'];
        if (family is! String || family.isEmpty) continue;
        final subsets = entry['subsets'];
        if (subsets is List && !subsets.contains('latin')) continue;
        final popularity = entry['popularity'];
        families.add(FathomFontFamily(
          family: family,
          category: entry['category'] is String
              ? entry['category'] as String
              : 'Sans Serif',
          popularity: popularity is int ? popularity : 9999,
        ));
      }
      families.sort((a, b) => a.popularity.compareTo(b.popularity));
      return List.unmodifiable(families);
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [family], registers it and keeps it for the next launch.
  Future<void> install(String family) async {
    if (_installed.contains(family)) return;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final cssUri = Uri.parse(_cssUrl).replace(queryParameters: {
        'family': family,
      });
      final request = await client.getUrl(cssUri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Google Fonts said ${response.statusCode}');
      }
      final css = await response.transform(utf8.decoder).join();
      final match = RegExp(r"url\((https://[^)]+\.ttf)\)").firstMatch(css);
      if (match == null) {
        throw const FormatException('That family has no downloadable TTF');
      }

      final fontRequest = await client.getUrl(Uri.parse(match.group(1)!));
      final fontResponse = await fontRequest.close();
      if (fontResponse.statusCode != HttpStatus.ok) {
        throw HttpException('Font file said ${fontResponse.statusCode}');
      }
      final bytes = await fontResponse
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          )
          .then((builder) => builder.takeBytes());
      if (bytes.isEmpty) throw const FormatException('Font file was empty');

      final dir = await _fontDirectory();
      final file = File('${dir.path}/${_fileName(family)}');
      await file.writeAsBytes(bytes, flush: true);

      final loader = FontLoader(family)..addFont(Future.value(_data(bytes)));
      await loader.load();
      _installed.add(family);
    } finally {
      client.close(force: true);
    }
  }
}
