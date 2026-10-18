import 'package:flutter/foundation.dart';

@immutable
class FathomTrack {
  const FathomTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    this.durationMs,
    this.dateAdded,
  });

  final int id;
  final String title;
  final String artist;
  final String uri;
  final int? durationMs;
  final int? dateAdded;

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
      durationMs: song.duration as int?,
      dateAdded: song.dateAdded as int?,
    );
  }

  factory FathomTrack.fromMap(Map<String, dynamic> map) => FathomTrack(
        id: (map['id'] as num?)?.toInt() ?? 0,
        title: (map['title'] as String?) ?? 'Untitled',
        artist: (map['artist'] as String?) ?? 'Unknown Artist',
        uri: (map['uri'] as String?) ?? '',
        durationMs: (map['duration'] as num?)?.toInt(),
        dateAdded: (map['dateAdded'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'uri': uri,
        'duration': durationMs,
        'dateAdded': dateAdded,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FathomTrack &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
