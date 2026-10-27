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

  /// Bytes already held for [videoId], or null when none were fetched yet.
  ///
  /// This is the read side the library uses for a device track that came from
  /// a download: the download itself puts its cover art here (see [remember]),
  /// so a row can show it without asking the network again and without knowing
  /// anything about the remote source.
  Uint8List? cachedForVideo(String videoId) => _memory[videoId];

  /// Keeps [bytes] for [videoId] so later readers find them without a request.
  ///
  /// A download has the cover art in hand already; remembering it is free and
  /// is what lets the library resolve the artwork of a fetched file whose
  /// MediaStore row carries none.
  void remember(String videoId, Uint8List bytes) {
    if (videoId.isEmpty || bytes.isEmpty) return;
    _memory[videoId] = Uint8List.fromList(bytes);
  }

  /// Returns the artwork for a remote item, or null if it cannot be fetched.
  ///
  /// Concurrent callers for the same item share one request.
  Future<Uint8List?> forVideo(String videoId, Uri? thumbUri) {
    // A remembered image needs no URL: a download resolves the cover art and
    // keeps it here, and that item's row may have arrived without a thumbnail.
    final cached = _memory[videoId];
    if (cached != null) return Future.value(cached);

    if (thumbUri == null || thumbUri.toString().isEmpty) {
      return Future.value(null);
    }

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
