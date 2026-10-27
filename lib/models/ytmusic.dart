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

/// YouTube's thumbnail URLs encode the size they serve, so this is more than a
/// curiosity: without it the choice between two variants is arbitrary.
///
/// Two shapes have to be understood, and they are not variations of one form:
///
/// * a rewritten URL carries the requested size as a query-style suffix, as in
///   `.../mqdefault.jpg=w320-h320-l90-rj`;
/// * a plain ytimg URL carries it only in the file name, as in
///   `.../maxresdefault.jpg` or `.../hqdefault.jpg`. A URL of this shape has no
///   `=w` at all, which is why the old reader reported every ytimg thumbnail as
///   unknown and the picker fell back to whatever came first.
final _thumbWidth = RegExp(r'=w(\d+)');

/// The width each ytimg file name serves.
///
/// These are YouTube's fixed presets, not rewrites: the name is the only
/// description of the image's size. `hq1`/`hq2`/`hq3` and the bare `1`/`2`/`3`
/// are the small squares the player UI uses.
const Map<String, int> _thumbPresetWidths = {
  'maxresdefault': 1280,
  'hq720': 1280,
  'sddefault': 640,
  'hqdefault': 480,
  'mqdefault': 320,
  'default': 120,
  'hq1': 120,
  'hq2': 120,
  'hq3': 120,
  '1': 120,
  '2': 120,
  '3': 120,
};

/// The width a thumbnail URL serves, or null when it does not say.
///
/// The extractor's `imagesToList` is a bare `images.map { it.url }`: it drops
/// NewPipe's own `width`/`height` fields and does not sort, so list order carries
/// no meaning at all and the URL is the only place the size survives. A rewrite
/// suffix wins over the file-name preset because it names the size actually
/// being requested, while the file name only names the original.
int? thumbWidthOf(String url) {
  if (url.isEmpty) return null;
  final match = _thumbWidth.firstMatch(url);
  if (match != null) {
    final width = int.tryParse(match.group(1)!);
    if (width != null) return width;
  }
  return _presetWidthOf(url);
}

/// Reads the size a ytimg file name encodes, or null for any other URL.
int? _presetWidthOf(String url) {
  final segments = Uri.tryParse(url)?.pathSegments;
  if (segments == null || segments.isEmpty) return null;

  var name = segments.last;
  // Older rewrites glued the suffix straight onto the file name without a `?`,
  // so cut at `=` before looking for the extension.
  final suffix = name.indexOf('=');
  if (suffix >= 0) name = name.substring(0, suffix);
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return _thumbPresetWidths[name.toLowerCase()];
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

/// Every usable URL in [urls], widest first, with unreadable sizes last.
///
/// This is the download's fallback order. A cover-art fetch wants the largest
/// image first, but the largest preset does not exist for every video: a
/// `maxresdefault` request can answer 404 where `hqdefault` exists. Trying the
/// sizes in order turns that into a smaller cover instead of no cover, and
/// deduplication keeps one image from being requested twice when the extractor
/// carries both the rewritten and the plain form of the same thumbnail.
List<String> rankedThumbnails(List<String> urls) {
  final seen = <String>{};
  final ranked = <String>[];
  for (final url in urls) {
    if (url.isEmpty) continue;
    if (!seen.add(url)) continue;
    ranked.add(url);
  }

  ranked.sort((a, b) {
    final left = thumbWidthOf(a);
    final right = thumbWidthOf(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  return ranked;
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
