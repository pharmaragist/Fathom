import 'dart:async';
import 'dart:ui' as ui;

import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

import '../models/ytmusic.dart';

enum YtQuality { low, high }

abstract class FathomYtSource {
  Future<void> initialize();

  bool get isReady;

  String? get error;

  Future<void> retry();

  /// Remote search results, yielded progressively as the backend finds them.
  /// Callers that care about a superseded search should guard on their own
  /// token; this stream has no notion of one.
  Stream<YtItem> search(
    String query, {
    required int limit,
    required YtQuality quality,
  });

  Future<Uri?> audioUri(String videoId);

  Future<Map<String, Uri>> audioUris(List<String> videoIds);
}

class FathomYtMusic implements FathomYtSource {
  FathomYtMusic({YtFlutterMusicapi? api}) : _api = api ?? YtFlutterMusicapi();

  final YtFlutterMusicapi _api;
  Future<void>? _initFuture;
  bool _ready = false;
  String? _error;

  @override
  bool get isReady => _ready;

  @override
  String? get error => _error;

  static String get deviceCountry {
    final code = ui.PlatformDispatcher.instance.locale.countryCode;
    final upper = code?.toUpperCase();
    return (upper != null && upper.length == 2) ? upper : 'US';
  }

  @override
  Future<void> initialize() => _initFuture ??= _initialize();

  @override
  Future<void> retry() {
    _initFuture = null;
    return initialize();
  }

  Future<void> _initialize() async {
    try {
      final response = await _api.initialize(country: deviceCountry);
      _ready = response.success;
      _error =
          _ready ? null : (response.error ?? 'YouTube Music did not start');
    } catch (e) {
      _ready = false;
      _error = e.toString();
    }
  }

  ThumbnailQuality _thumb(YtQuality quality) => switch (quality) {
        YtQuality.low => ThumbnailQuality.low,
        YtQuality.high => ThumbnailQuality.veryHigh,
      };

  @override
  Stream<YtItem> search(
    String query, {
    required int limit,
    required YtQuality quality,
  }) async* {
    if (query.trim().isEmpty) return;
    await initialize();
    if (!_ready) return;

    yield* _api
        .streamSearchResults(
          query: query.trim(),
          limit: limit,
          thumbQuality: _thumb(quality),
          includeAudioUrl: false,
          includeAlbumArt: true,
        )
        .map(
          (song) => YtItem(
            videoId: song.videoId,
            title: song.title,
            artist: song.artists,
            duration: parseYtDuration(song.duration),
            thumbUri: Uri.tryParse(song.albumArt ?? ''),
          ),
        );
  }

  @override
  Future<Uri?> audioUri(String videoId) async {
    final resolved = await audioUris([videoId]);
    return resolved[videoId];
  }

  @override
  Future<Map<String, Uri>> audioUris(List<String> videoIds) async {
    if (videoIds.isEmpty) return const {};
    await initialize();
    if (!_ready) return const {};

    final response = await _api.getAudioUrlsFastBatch(videoIds: videoIds);
    final resolved = <String, Uri>{};
    for (final entry in response.entries) {
      final url = entry.value;
      if (url == null || url.isEmpty) continue;
      final uri = Uri.tryParse(url);
      if (uri != null) resolved[entry.key] = uri;
    }
    return resolved;
  }

  Future<void> dispose() => _api.dispose();
}
