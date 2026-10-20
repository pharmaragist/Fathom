import 'dart:io';
import 'dart:typed_data';

/// Fetches and caches remote artwork.
///
/// Keys are `videoId`s, not the thumbnail URL, because the URL is a
/// googleusercontent rewrite that changes with the requested quality while
/// the item stays the same.
class FathomArtCache {
  FathomArtCache._();

  static final FathomArtCache instance = FathomArtCache._();

  final Map<String, Uint8List> _memory = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  /// Returns the artwork for a remote item, or null if it cannot be fetched.
  ///
  /// Concurrent callers for the same item share one request.
  Future<Uint8List?> forVideo(String videoId, Uri? thumbUri) {
    if (thumbUri == null || thumbUri.toString().isEmpty) {
      return Future.value(null);
    }

    final cached = _memory[videoId];
    if (cached != null) return Future.value(cached);

    return _inFlight[videoId] ??= _fetch(videoId, thumbUri);
  }

  Future<Uint8List?> _fetch(String videoId, Uri thumbUri) async {
    try {
      final request = await _http.getUrl(thumbUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;

      final bytes = await response
          .fold<BytesBuilder>(
            BytesBuilder(),
            (builder, chunk) => builder..add(chunk),
          )
          .then((builder) => builder.takeBytes());

      if (bytes.isEmpty) return null;
      _memory[videoId] = Uint8List.fromList(bytes);
      return _memory[videoId];
    } catch (_) {
      // A missing thumbnail must never break a row or a playback start.
      return null;
    } finally {
      _inFlight.remove(videoId);
    }
  }

  /// True when the item's artwork is already in memory.
  bool has(String videoId) => _memory.containsKey(videoId);

  void clear() => _memory.clear();
}
