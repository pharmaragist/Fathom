import 'package:flutter/foundation.dart';

/// The largest thumbnail worth requesting for a list row.
///
/// A row renders at a few dozen logical pixels, so anything past this is
/// downloaded and thrown away by the image decoder.
const int kThumbRowMaxWidth = 320;

/// The smallest thumbnail a thrifty (`dataSave`) search asks for.
const int kThumbThriftyMaxWidth = 120;

/// The largest thumbnail worth embedding in a downloaded file.
///
/// This one is written into the file's own cover art, where it is what a media
/// player, a lock screen and any other app shows for the track from then on.
/// YouTube's own top size is 1280x720, so this asks for real artwork without
/// pretending a phone needs more.
const int kThumbArtMaxWidth = 1280;

/// YouTube's thumbnail URLs encode the size they serve, and the sizes overlap
/// between the entries, so this is more than a curiosity: without it the choice
/// between two 320px variants is arbitrary.
final _thumbWidth = RegExp(r'=w(\d+)');

/// The width a thumbnail URL serves, or null when it does not say.
///
/// The extractor's `imagesToList` is a bare `images.map { it.url }`: it drops
/// NewPipe's own `width`/`height` fields and does not sort, so list order carries
/// no meaning at all and the URL is the only place the size survives.
int? thumbWidthOf(String url) {
  final match = _thumbWidth.firstMatch(url);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Picks the thumbnail closest to [maxWidth] without going over it.
///
/// Selecting by width is the whole point: the extractor hands over an unsorted
/// list, so taking its first or last entry is arbitrary and can put a 48px
/// square in a row that had room for a real image.
///
/// A URL whose width cannot be read ranks last rather than being dropped: the
/// YouTube shape is stable, but a thumbnail that never renders is a worse
/// failure than one that renders at a size nobody promised.
String? pickThumbnail(List<String> urls, {required int maxWidth}) {
  String? best;
  var bestWidth = -1;
  String? unknown;

  for (final url in urls) {
    if (url.isEmpty) continue;
    final width = thumbWidthOf(url);
    if (width == null) {
      unknown ??= url;
      continue;
    }
    if (width <= maxWidth && width > bestWidth) {
      best = url;
      bestWidth = width;
    }
  }
  if (best != null) return best;

  // Nothing fit under the cap, so the cap was smaller than every size the item
  // carries. The smallest available is the closest answer to what was asked
  // for, and an unreadable URL is still better than no artwork at all.
  return _smallestByWidth(urls) ?? unknown;
}

/// The narrowest URL in [urls], or null when none of them reports a width.
String? _smallestByWidth(List<String> urls) {
  String? best;
  var bestWidth = -1;
  for (final url in urls) {
    if (url.isEmpty) continue;
    final width = thumbWidthOf(url);
    if (width == null) continue;
    if (bestWidth == -1 || width < bestWidth) {
      best = url;
      bestWidth = width;
    }
  }
  return best;
}

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
    this.thumbUris = const [],
  });

  final String videoId;
  final String title;
  final String artist;

  /// Length in seconds, as the extractor reports it.
  final int? duration;

  /// The thumbnail this row should display, already chosen for a list row.
  final Uri? thumbUri;

  /// Every thumbnail size the item carries, in the extractor's own order.
  ///
  /// Kept alongside [thumbUri] because the choice is not final: a download
  /// embeds real cover art and wants a far larger image than a row does, so it
  /// has to pick again from the same list at its own cap. Carrying the list is
  /// what makes that re-pick free — the extractor hands these over with the
  /// streams, so nothing has to ask YouTube twice.
  final List<String> thumbUris;
}
