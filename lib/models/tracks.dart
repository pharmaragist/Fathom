import 'package:flutter/foundation.dart';

import 'ytmusic.dart';

/// Where a track's audio lives.
enum TrackOrigin {
  /// A file on this device, found by the media scan.
  device,

  /// A YouTube Music item with no file on this device yet. It carries no
  /// address and cannot be played; it is a thing to download.
  ytMusic,
}

@immutable
class FathomTrack {
  const FathomTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    required this.origin,
    this.videoId,
    this.thumbUri,
    this.thumbUris = const [],
    this.durationMs,
    this.dateAdded,
  });

  /// Builds a track from a device file.
  factory FathomTrack.fromDevice(dynamic song) {
    final uri = (song.uri as String?) ?? '';
    final artist = song.artist as String?;
    return FathomTrack(
      id: song.id as int,
      title: ((song.title as String?)?.trim().isNotEmpty ?? false)
          ? (song.title as String).trim()
          : 'Untitled',
      artist: (artist == null || artist.trim().isEmpty)
          ? 'Unknown Artist'
          : artist.trim(),
      uri: uri,
      origin: TrackOrigin.device,
      durationMs: song.duration as int?,
      dateAdded: song.dateAdded as int?,
    );
  }

  /// Builds a track from a remote result.
  ///
  /// `uri` is empty on purpose: there is nothing on this device to point at
  /// yet. A remote address is never stored, because it expires within hours —
  /// it is resolved at download time and used once.
  factory FathomTrack.yt(YtItem item) => FathomTrack(
        // MediaStore ids are positive; a hash can be anything, and equality
        // checks the videoId for remote tracks anyway.
        id: item.videoId.hashCode,
        title: item.title,
        artist: item.artist,
        uri: '',
        origin: TrackOrigin.ytMusic,
        videoId: item.videoId,
        thumbUri: item.thumbUri,
        thumbUris: item.thumbUris,
        durationMs: item.duration == null ? null : item.duration! * 1000,
      );

  final int id;
  final String title;
  final String artist;
  final String uri;
  final TrackOrigin origin;

  /// Set for [TrackOrigin.ytMusic] tracks; identifies the item everywhere.
  final String? videoId;

  /// The address to fetch this track's cover art from during a download, or
  /// null when the item carries no artwork.
  ///
  /// Deliberately the largest of [thumbUris] rather than [thumbUri]: a download
  /// writes the image into the file's own tag, where it outlives this app and
  /// is what every other player will show. [thumbUri] was chosen for a list row
  /// and is far too small for that — and with `dataSave` on it is deliberately
  /// tiny, so reusing it would bake the smallest possible image into the file
  /// permanently, which no later change could undo.
  String? get artworkUrl {
    final chosen = thumbUris.isEmpty
        ? thumbUri?.toString()
        : pickThumbnail(thumbUris, maxWidth: kThumbArtMaxWidth);
    return chosen;
  }

  /// Thumbnail for remote tracks. Device tracks read art from the media store.
  final Uri? thumbUri;

  /// Every thumbnail size the item carries.
  ///
  /// Kept so a download can pick again at its own cap; see [artworkUrl].
  final List<String> thumbUris;

  final int? durationMs;
  final int? dateAdded;

  /// This track as plain JSON-safe values, for the player's saved queue.
  ///
  /// Every field that makes a track playable is included, because a restored
  /// queue is rebuilt from these maps before the library scan has finished:
  /// [uri] and [origin] decide whether it can play, the rest only describe it.
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'uri': uri,
        'origin': origin.name,
        'videoId': videoId,
        'thumbUri': thumbUri?.toString(),
        'thumbUris': thumbUris,
        'durationMs': durationMs,
        'dateAdded': dateAdded,
      };

  /// Reads a track written by [toJson], or null when the map cannot name one.
  ///
  /// The reader is tolerant on purpose: saved state outlives a build, and an
  /// older payload stored [origin] as an index. A missing or unknown origin
  /// falls back to [TrackOrigin.device], which is the only origin that can ever
  /// be in a saved queue.
  static FathomTrack? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! int) return null;

    final origin = switch (value['origin']) {
      final String name => TrackOrigin.values.firstWhere(
          (o) => o.name == name,
          orElse: () => TrackOrigin.device,
        ),
      final int index => index == TrackOrigin.ytMusic.index
          ? TrackOrigin.ytMusic
          : TrackOrigin.device,
      _ => TrackOrigin.device,
    };

    final title = value['title'];
    final artist = value['artist'];
    final uri = value['uri'];
    final duration = value['durationMs'];
    final added = value['dateAdded'];
    final thumbs = value['thumbUris'];

    return FathomTrack(
      id: id,
      title: title is String && title.isNotEmpty ? title : 'Untitled',
      artist: artist is String && artist.isNotEmpty ? artist : 'Unknown Artist',
      uri: uri is String ? uri : '',
      origin: origin,
      videoId: value['videoId'] is String ? value['videoId'] as String : null,
      thumbUri: value['thumbUri'] is String
          ? Uri.tryParse(value['thumbUri'] as String)
          : null,
      thumbUris: thumbs is List
          ? [
              for (final thumb in thumbs)
                if (thumb is String) thumb
            ]
          : const [],
      durationMs: duration is int ? duration : null,
      dateAdded: added is int ? added : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FathomTrack &&
          runtimeType == other.runtimeType &&
          origin == other.origin &&
          (origin == TrackOrigin.device
              ? id == other.id
              : videoId == other.videoId);

  @override
  int get hashCode =>
      Object.hash(origin, origin == TrackOrigin.device ? id : videoId);
}
