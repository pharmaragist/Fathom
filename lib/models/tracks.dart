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
        durationMs: item.duration == null ? null : item.duration! * 1000,
      );

  final int id;
  final String title;
  final String artist;
  final String uri;
  final TrackOrigin origin;

  /// Set for [TrackOrigin.ytMusic] tracks; identifies the item everywhere.
  final String? videoId;
  String? get artworkUrl => thumbUri?.toString();

  /// Thumbnail for remote tracks. Device tracks read art from the media store.
  final Uri? thumbUri;
  final int? durationMs;
  final int? dateAdded;

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
