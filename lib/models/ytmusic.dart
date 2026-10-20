import 'package:flutter/foundation.dart';

/// One item returned by the YouTube Music source.
///
/// Deliberately narrower than a [FathomTrack]: it is a remote result with no
/// device file behind it, and it only becomes a track once the queue adopts it.
@immutable
class YtItem {
  const YtItem({
    required this.videoId,
    required this.title,
    required this.artist,
    this.duration,
    this.thumbUri,
  });

  final String videoId;
  final String title;
  final String artist;

  /// Length in seconds. The API reports `"3:32"`; see [parseYtDuration].
  final int? duration;
  final Uri? thumbUri;
}

/// Parses the API's human duration string into seconds.
///
/// Accepts `mm:ss` and `h:mm:ss`. Anything else — empty, missing, or a
/// non-numeric shape — yields null rather than a guessed zero, so the UI can
/// fall back to showing nothing instead of `0:00`.
int? parseYtDuration(String? raw) {
  if (raw == null) return null;
  final parts = raw.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;

  var seconds = 0;
  for (final part in parts) {
    final value = int.tryParse(part.trim());
    if (value == null) return null;
    seconds = seconds * 60 + value;
  }
  return seconds;
}
