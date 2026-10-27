import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/common/library.dart';
import 'package:fathom/models/tracks.dart';

FathomTrack device(int id, {String? title}) {
  return FathomTrack(
    id: id,
    title: title ?? 'Track $id',
    artist: 'Artist',
    uri: 'content://media/external/audio/media/$id',
    origin: TrackOrigin.device,
    durationMs: 180000,
    dateAdded: 1000 + id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an identical rescan publishes nothing', () {
    final library = FathomLibrary();
    addTearDown(library.dispose);

    library.applyScan([device(1), device(2)]);
    expect(library.status, FathomLibraryStatus.ready);
    final before = library.tracks;
    final revision = library.revision;

    var notifications = 0;
    library.addListener(() => notifications++);

    // Fresh FathomTrack instances, same identity and metadata — exactly what
    // the media store returns when nothing has changed.
    library.applyScan([device(1), device(2)]);

    expect(notifications, 0);
    expect(library.revision, revision);
    expect(identical(library.tracks, before), isTrue);
    expect(library.lastDelta.isEmpty, isTrue);
  });

  test('a changed rescan publishes once and carries the delta', () {
    final library = FathomLibrary();
    addTearDown(library.dispose);

    library.applyScan([device(1), device(2)]);

    var notifications = 0;
    library.addListener(() => notifications++);

    library.applyScan([device(3, title: 'Track 0'), device(1), device(2)]);

    expect(notifications, 1);
    expect(library.revision, 2);
    expect(library.tracks.length, 3);
    expect(library.lastDelta.addedIds, [3]);
    expect(library.lastDelta.removedIds, isEmpty);
    expect(library.lastDelta.movedIds, isEmpty);
  });

  test('a metadata-only rescan publishes once and is reported as updated', () {
    final library = FathomLibrary();
    addTearDown(library.dispose);

    library.applyScan([device(1, title: 'Old title')]);

    var notifications = 0;
    library.addListener(() => notifications++);

    library.applyScan([device(1, title: 'New title')]);

    expect(notifications, 1);
    expect(library.lastDelta.updatedIds, [1]);
    expect(library.tracks.single.title, 'New title');
  });

  test('the first scan moves the status to ready and notifies once', () {
    final library = FathomLibrary();
    addTearDown(library.dispose);

    var notifications = 0;
    library.addListener(() => notifications++);

    library.applyScan([device(1)]);

    expect(notifications, 1);
    expect(library.status, FathomLibraryStatus.ready);
  });

  test('a full load path emits nothing when the media store is unchanged',
      () async {
    const channel = MethodChannel('com.lucasjosino.on_audio_query');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Map<String, Object?> song(int id, String title) => {
          '_id': id,
          '_uri': 'content://media/external/audio/media/$id',
          'title': title,
          'artist': 'Artist',
          'duration': 180000,
          'date_added': 1000 + id,
        };
    var rows = <Map<String, Object?>>[song(1, 'One'), song(2, 'Two')];

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'permissionsStatus':
          return true;
        case 'querySongs':
          return rows;
      }
      return null;
    });

    final library = FathomLibrary();
    addTearDown(library.dispose);

    await library.load(grantIfMissing: false);
    expect(library.status, FathomLibraryStatus.ready);

    var notifications = 0;
    library.addListener(() => notifications++);

    // A rescan must not pass through `loading`: that notification alone would
    // rebuild the page into a spinner and lose the scroll view.
    await library.load(grantIfMissing: false);
    expect(notifications, 0);

    rows = [...rows, song(3, 'Three')];
    await library.load(grantIfMissing: false);
    expect(notifications, 1);
    expect(library.lastDelta.addedIds, [3]);
  });
}
