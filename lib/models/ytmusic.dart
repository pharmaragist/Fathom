import 'package:flutter/foundation.dart';

/// One item returned by the YouTube Music source.
///
/// Deliberately narrower than a [FathomTrack]: it is a remote result with no
/// device file behind it. It never joins a play queue — an item becomes music
/// only once it has been downloaded and the library scan has found the file.
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

  /// Length in seconds, as the extractor reports it.
  final int? duration;
  final Uri? thumbUri;
}
