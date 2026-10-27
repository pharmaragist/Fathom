import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/common/selection.dart';
import 'package:fathom/models/tracks.dart';

FathomTrack _device(int id) => FathomTrack(
      id: id,
      title: 'Track $id',
      artist: 'Artist $id',
      uri: 'content://media/audio/$id',
      origin: TrackOrigin.device,
    );

FathomTrack _remote(String videoId) => FathomTrack(
      id: videoId.hashCode,
      title: 'Remote $videoId',
      artist: 'Channel',
      uri: '',
      origin: TrackOrigin.ytMusic,
      videoId: videoId,
    );

void main() {
  test('selection starts inactive and empty', () {
    final selection = FathomSelection();

    expect(selection.active, isFalse);
    expect(selection.count, 0);
    expect(selection.keys, isEmpty);
  });

  test('begin enters the mode without selecting anything', () {
    final selection = FathomSelection();
    var notifications = 0;
    selection.addListener(() => notifications++);

    selection.begin();

    expect(selection.active, isTrue);
    expect(selection.count, 0);
    expect(notifications, 1);

    selection.begin();
    expect(notifications, 1, reason: 'already active is a no-op');
  });

  test('toggling a device track selects and deselects it', () {
    final selection = FathomSelection();
    final track = _device(7);

    selection.toggle(track);
    expect(selection.active, isTrue);
    expect(selection.isSelected(track), isTrue);
    expect(selection.count, 1);

    selection.toggle(track);
    expect(selection.isSelected(track), isFalse);
    expect(selection.count, 0);
    expect(selection.active, isTrue, reason: 'deselecting is not leaving');
  });

  test('a remote item is never selectable and does not notify', () {
    final selection = FathomSelection();
    var notifications = 0;
    selection.addListener(() => notifications++);

    final remote = _remote('abc123');
    selection.toggle(remote);

    expect(selection.active, isFalse);
    expect(selection.isSelected(remote), isFalse);
    expect(selection.count, 0);
    expect(notifications, 0);
  });

  test('selectAll skips remote items and tolerates duplicates', () {
    final selection = FathomSelection();
    final first = _device(1);
    final second = _device(2);
    final remote = _remote('abc123');

    selection.selectAll([first, remote, second, first]);

    expect(selection.active, isTrue);
    expect(selection.count, 2);
    expect(selection.isSelected(first), isTrue);
    expect(selection.isSelected(second), isTrue);
    expect(selection.isSelected(remote), isFalse);
  });

  test('toggleAll selects everything, then clears without leaving', () {
    final selection = FathomSelection();
    final tracks = [_device(1), _device(2), _remote('abc123')];

    selection.toggleAll(tracks);
    expect(selection.active, isTrue);
    expect(selection.count, 2);

    selection.toggleAll(tracks);
    expect(selection.active, isTrue);
    expect(selection.count, 0);

    selection.toggleAll(tracks);
    expect(selection.count, 2);
  });

  test('exit leaves the mode and drops every key', () {
    final selection = FathomSelection();
    final track = _device(1);

    selection.toggle(track);
    var notifications = 0;
    selection.addListener(() => notifications++);

    selection.exit();

    expect(selection.active, isFalse);
    expect(selection.count, 0);
    expect(selection.isSelected(track), isFalse);
    expect(notifications, 1);

    selection.exit();
    expect(notifications, 1, reason: 'already exited is a no-op');
  });

  test('keys are a read-only view of the selection', () {
    final selection = FathomSelection();
    selection.toggle(_device(1));

    expect(
      () => selection.keys.add((TrackOrigin.device, 2)),
      throwsUnsupportedError,
    );
  });

  test('deleting selected files drops only the ids that are gone', () {
    final selection = FathomSelection();
    final first = _device(1);
    final second = _device(2);
    selection.selectAll([first, second]);

    selection.removeDeleted({1});

    expect(selection.active, isTrue);
    expect(selection.isSelected(first), isFalse);
    expect(selection.isSelected(second), isTrue);
    expect(selection.count, 1);

    selection.removeDeleted({2});
    expect(selection.active, isFalse);
    expect(selection.count, 0);
  });
}
