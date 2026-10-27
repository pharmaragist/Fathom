import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/tracks.dart';

/// The player persists its queue as JSON so a cold start can rebuild every
/// source, not just the current one. These tests cover the track half of that
/// payload: a full round trip, the legacy origin encoding, and malformed data.
void main() {
  test('a device track round-trips through stored JSON', () {
    const track = FathomTrack(
      id: 42,
      title: 'Night Drive',
      artist: 'Fathom',
      uri: 'content://media/external/audio/media/42',
      origin: TrackOrigin.device,
      durationMs: 215000,
      dateAdded: 1700000000,
    );

    final stored = jsonDecode(jsonEncode(track.toJson()));
    final restored = FathomTrack.fromJson(stored);

    expect(restored, track);
    expect(restored!.uri, track.uri);
    expect(restored.title, track.title);
    expect(restored.artist, track.artist);
    expect(restored.durationMs, track.durationMs);
    expect(restored.dateAdded, track.dateAdded);
    expect(restored.origin, TrackOrigin.device);
  });

  test('a remote item keeps the fields that identify it', () {
    const track = FathomTrack(
      id: -7,
      title: 'Remote',
      artist: 'Someone',
      uri: '',
      origin: TrackOrigin.ytMusic,
      videoId: 'abc123',
      thumbUri: null,
      thumbUris: ['https://img/1.jpg', 'https://img/2.jpg'],
    );

    final restored =
        FathomTrack.fromJson(jsonDecode(jsonEncode(track.toJson())));

    expect(restored, track);
    expect(restored!.videoId, 'abc123');
    expect(restored.thumbUris, track.thumbUris);
  });

  test('an origin saved as its old index still decodes', () {
    final restored = FathomTrack.fromJson({
      'id': 9,
      'title': 'Old payload',
      'artist': 'Fathom',
      'uri': 'content://media/external/audio/media/9',
      'origin': TrackOrigin.device.index,
    });

    expect(restored, isNotNull);
    expect(restored!.origin, TrackOrigin.device);
  });

  test('a map without a usable id is rejected instead of guessed', () {
    expect(FathomTrack.fromJson(null), isNull);
    expect(FathomTrack.fromJson(<String, Object?>{'title': 'x'}), isNull);
    expect(FathomTrack.fromJson('not a track'), isNull);
  });

  test('a missing title or artist falls back to the documented labels', () {
    final restored = FathomTrack.fromJson({
      'id': 3,
      'uri': 'content://media/external/audio/media/3',
      'origin': 'device',
    });

    expect(restored!.title, 'Untitled');
    expect(restored.artist, 'Unknown Artist');
    expect(restored.thumbUris, isEmpty);
  });
}
