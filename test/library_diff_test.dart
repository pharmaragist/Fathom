import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/common/library_diff.dart';
import 'package:fathom/models/tracks.dart';

FathomTrack device(
  int id, {
  String? title,
  String? artist,
  int? dateAdded,
}) {
  return FathomTrack(
    id: id,
    title: title ?? 'Track $id',
    artist: artist ?? 'Artist',
    uri: 'content://media/external/audio/media/$id',
    origin: TrackOrigin.device,
    durationMs: 180000 + id,
    dateAdded: dateAdded ?? 1000 + id,
  );
}

void main() {
  group('reconcileLibraryTracks', () {
    test('an identical scan is empty and reuses the old instances', () {
      final first = [device(1), device(2), device(3)];
      final result = reconcileLibraryTracks(first, [
        device(1),
        device(2),
        device(3),
      ]);

      expect(result.delta.isEmpty, isTrue);
      expect(result.delta.addedIds, isEmpty);
      expect(result.delta.removedIds, isEmpty);
      expect(result.delta.movedIds, isEmpty);
      expect(result.delta.updatedIds, isEmpty);
      // The page caches row widgets by track identity; keeping the old
      // instances is what lets it skip rebuilding them.
      expect(identical(result.tracks[0], first[0]), isTrue);
      expect(identical(result.tracks[1], first[1]), isTrue);
      expect(identical(result.tracks[2], first[2]), isTrue);
    });

    test('an insert at the top reports one added id and no moved ids', () {
      final previous = [device(1), device(2), device(3)];
      final inserted = device(9, title: 'Track 9');
      final result = reconcileLibraryTracks(previous, [
        inserted,
        ...previous,
      ]);

      expect(result.delta.addedIds, [9]);
      expect(result.delta.removedIds, isEmpty);
      // Every old index shifted by one, but no survivor changed its rank
      // among the survivors, so nothing moved.
      expect(result.delta.movedIds, isEmpty);
      expect(result.delta.updatedIds, isEmpty);
      expect(result.tracks.first, same(inserted));
    });

    test('a removal reports exactly the missing id', () {
      final previous = [device(1), device(2), device(3)];
      final result = reconcileLibraryTracks(previous, [
        previous[0],
        previous[2],
      ]);

      expect(result.delta.removedIds, [2]);
      expect(result.delta.addedIds, isEmpty);
      expect(result.delta.movedIds, isEmpty);
    });

    test('a reorder reports the rows whose relative order changed', () {
      final previous = [device(1), device(2), device(3)];
      final result = reconcileLibraryTracks(previous, [
        previous[1],
        previous[0],
        previous[2],
      ]);

      expect(result.delta.addedIds, isEmpty);
      expect(result.delta.removedIds, isEmpty);
      expect(result.delta.movedIds, containsAll(<int>[1, 2]));
      // The row that stayed last changed neither rank nor metadata.
      expect(result.delta.movedIds, isNot(contains(3)));
    });

    test('a metadata change is reported as updated, not added', () {
      final previous = [device(1, title: 'Old title')];
      final result = reconcileLibraryTracks(previous, [
        device(1, title: 'New title'),
      ]);

      expect(result.delta.addedIds, isEmpty);
      expect(result.delta.removedIds, isEmpty);
      expect(result.delta.updatedIds, [1]);
      expect(result.delta.isEmpty, isFalse);
      expect(result.tracks.single.title, 'New title');
    });

    test('a metadata change that moves the row is both updated and moved', () {
      final previous = [
        device(1, title: 'A'),
        device(2, title: 'B'),
      ];
      final result = reconcileLibraryTracks(previous, [
        device(2, title: 'B'),
        device(1, title: 'Z'),
      ]);

      expect(result.delta.updatedIds, [1]);
      expect(result.delta.movedIds, contains(1));
    });

    test('remote identity is the video id, not the hashed id', () {
      const a = FathomTrack(
        id: 1,
        title: 'A',
        artist: 'Artist',
        uri: '',
        origin: TrackOrigin.ytMusic,
        videoId: 'video-a',
      );
      const b = FathomTrack(
        id: 99,
        title: 'A',
        artist: 'Artist',
        uri: '',
        origin: TrackOrigin.ytMusic,
        videoId: 'video-a',
      );
      final result = reconcileLibraryTracks([a], [b]);

      expect(result.delta.isEmpty, isTrue);
      expect(result.tracks.single, same(a));
    });
  });
}
