import 'package:flutter/foundation.dart';

import '../models/tracks.dart';

/// What identifies a track across two media scans.
///
/// A device track is its media id; a remote item is its video id. The pair is
/// wrapped with the origin because the two id spaces are unrelated — a hash
/// can equal a media row id by accident.
typedef LibraryTrackKey = (TrackOrigin origin, Object identity);

/// The stable identity of [track] across scans.
LibraryTrackKey libraryTrackKey(FathomTrack track) => (
      track.origin,
      track.origin == TrackOrigin.device
          ? track.id
          : (track.videoId ?? track.id),
    );

/// Whether two scans describe the same row.
///
/// [FathomTrack] equality deliberately stops at identity, because the player
/// queues by identity. A scan, however, can return new metadata for the same
/// media id (a file retagged outside Fathom), and the UI reads every field
/// here, so a rescan that changes one of them is not a no-op.
bool sameLibraryTrackMetadata(FathomTrack a, FathomTrack b) =>
    a.title == b.title &&
    a.artist == b.artist &&
    a.uri == b.uri &&
    a.durationMs == b.durationMs &&
    a.dateAdded == b.dateAdded &&
    a.thumbUri == b.thumbUri &&
    listEquals(a.thumbUris, b.thumbUris);

/// The change one scan made to the library.
///
/// [added], [removed] and [moved] are structural; [updated] names rows whose
/// identity survived but whose metadata the UI reads changed. All four lists
/// are in scan order, and the id getters exist because that is what a caller
/// needs to key an animation or a row.
@immutable
class FathomLibraryDelta {
  const FathomLibraryDelta({
    this.added = const [],
    this.removed = const [],
    this.moved = const [],
    this.updated = const [],
  });

  static const FathomLibraryDelta empty = FathomLibraryDelta();

  final List<FathomTrack> added;
  final List<FathomTrack> removed;

  /// Rows present before and after whose order relative to the other surviving
  /// rows changed. A row merely shifted by an insert or a removal is not
  /// moved: its rank among survivors is unchanged, which is what makes this
  /// list small on the ordinary one-file scan.
  final List<FathomTrack> moved;

  /// Rows whose identity survived but whose metadata changed.
  final List<FathomTrack> updated;

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && moved.isEmpty && updated.isEmpty;

  List<int> get addedIds => [for (final t in added) t.id];
  List<int> get removedIds => [for (final t in removed) t.id];
  List<int> get movedIds => [for (final t in moved) t.id];
  List<int> get updatedIds => [for (final t in updated) t.id];
}

/// Compares a scan against the library the UI already holds.
///
/// Returns the delta and the list to publish. The list is in [scanned] order,
/// but a row whose identity and metadata both survived is the *old* instance:
/// the page keys its row widgets by object identity, so reusing the instance
/// is what lets an unchanged row keep its element (and its running animation)
/// across a scan.
///
/// This is a pure function on purpose. It needs no media store, no plugin and
/// no notifier, so the add/remove/move/update rules are unit-tested directly.
({FathomLibraryDelta delta, List<FathomTrack> tracks}) reconcileLibraryTracks(
  List<FathomTrack> previous,
  List<FathomTrack> scanned,
) {
  // The common scan is the idle one: same rows, same order, same metadata.
  // Answering it before any map or list is built keeps a rescan that changes
  // nothing allocation-free, which is the point of notifying nobody.
  if (previous.length == scanned.length) {
    var same = true;
    for (var i = 0; i < previous.length; i++) {
      final old = previous[i];
      final next = scanned[i];
      if (libraryTrackKey(old) != libraryTrackKey(next) ||
          !sameLibraryTrackMetadata(old, next)) {
        same = false;
        break;
      }
    }
    if (same) {
      return (delta: FathomLibraryDelta.empty, tracks: previous);
    }
  }

  final oldByKey = <LibraryTrackKey, FathomTrack>{};
  for (final track in previous) {
    oldByKey[libraryTrackKey(track)] = track;
  }
  final scannedKeys = <LibraryTrackKey>{
    for (final track in scanned) libraryTrackKey(track),
  };

  final added = <FathomTrack>[];
  final updated = <FathomTrack>[];
  final merged = <FathomTrack>[];
  for (final track in scanned) {
    final key = libraryTrackKey(track);
    final old = oldByKey[key];
    if (old == null) {
      added.add(track);
      merged.add(track);
    } else if (sameLibraryTrackMetadata(old, track)) {
      merged.add(old);
    } else {
      updated.add(track);
      merged.add(track);
    }
  }

  final removed = <FathomTrack>[
    for (final track in previous)
      if (!scannedKeys.contains(libraryTrackKey(track))) track,
  ];

  // A row is moved only when its position *among the rows that survived both
  // scans* changes. Inserting a file at the top shifts every index, but no
  // survivor's rank moves, so a one-file scan reports one added row and no
  // moved rows.
  final oldRank = <LibraryTrackKey, int>{};
  var rank = 0;
  for (final track in previous) {
    final key = libraryTrackKey(track);
    if (scannedKeys.contains(key)) oldRank[key] = rank++;
  }
  final newRank = <LibraryTrackKey, int>{};
  rank = 0;
  for (final track in scanned) {
    final key = libraryTrackKey(track);
    if (oldByKey.containsKey(key)) newRank[key] = rank++;
  }

  final moved = <FathomTrack>[];
  for (var i = 0; i < scanned.length; i++) {
    final key = libraryTrackKey(scanned[i]);
    if (oldByKey.containsKey(key) && newRank[key] != oldRank[key]) {
      moved.add(merged[i]);
    }
  }

  return (
    delta: FathomLibraryDelta(
      added: List.unmodifiable(added),
      removed: List.unmodifiable(removed),
      moved: List.unmodifiable(moved),
      updated: List.unmodifiable(updated),
    ),
    tracks: List.unmodifiable(merged),
  );
}
