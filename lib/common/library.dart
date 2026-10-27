import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../models/tracks.dart';
import 'library_diff.dart';

enum FathomLibraryStatus { idle, permissionNeeded, loading, ready, failure }

class FathomLibrary extends ChangeNotifier {
  static const MethodChannel _deleteChannel =
      MethodChannel('pharmaracist.fathom/library');

  final OnAudioQuery _plugin = OnAudioQuery();
  final Map<int, Future<Uint8List?>> _artCache = {};
  final Map<int, Uint8List> _artBytes = {};

  static const _snapshotName = 'library.snapshot.v1.json';
  bool _restored = false;
  Future<void> _snapshotWrite = Future.value();

  /// Artwork for a device track whose MediaStore row has none.
  ///
  /// The missing piece is a remote one — a fetched file's cover was cached by
  /// the download under its `videoId`, while a library track is known by its
  /// media id — so this is a seam rather than an import: the library must not
  /// depend on the download service, and `main` wires the two records together
  /// once, after both exist. The callback may await the manifest read; returning
  /// null means there is no fallback image, not that the call failed.
  ///
  /// Every consumer of [artFor] inherits it: rows, the mini player, Now Playing
  /// and the palette extraction all go through this one cache.
  Future<Uint8List?> Function(int mediaId)? fallbackArtFor;

  FathomLibraryStatus _status = FathomLibraryStatus.idle;
  List<FathomTrack> _tracks = const [];

  /// The change the most recent scan decided on, or [FathomLibraryDelta.empty]
  /// after a scan that changed nothing. A surface that needs to react to one
  /// specific row can read this instead of diffing [tracks] itself; the list
  /// widget consumes the same information through its stable row keys.
  FathomLibraryDelta _delta = FathomLibraryDelta.empty;

  /// Bumped whenever the track list is actually replaced.
  ///
  /// The page memoises on this rather than list identity: it reads `tracks`
  /// without a selector, and a metadata-only update keeps the same identities,
  /// which list equality — and provider's deep collection comparison — would
  /// miss. A scan that changes nothing does not bump it.
  int _revision = 0;

  /// Drops a scan whose answer arrived after a newer scan started.
  int _scanGeneration = 0;

  AppLifecycleListener? _lifecycleListener;

  FathomLibrary() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (_status == FathomLibraryStatus.ready) {
          load(grantIfMissing: false);
        }
      },
    );
  }

  FathomLibraryStatus get status => _status;

  /// The current snapshot. Never mutated in place: a surface that selects it
  /// compares lists, and a list mutated behind a cached selection would never
  /// report a change.
  List<FathomTrack> get tracks => _tracks;

  FathomLibraryDelta get lastDelta => _delta;
  int get revision => _revision;

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<Uint8List?> artFor(int id) {
    final cached = _artBytes[id];
    if (cached != null) return Future.value(cached);
    return _artCache.putIfAbsent(id, () => _fetchArtwork(id));
  }

  /// Artwork already decoded into memory, or null while it is still loading.
  ///
  /// A destination route uses this to paint the same image the source row was
  /// already showing, instead of flashing the placeholder while the future
  /// completes.
  Uint8List? cachedArtFor(int id) => _artBytes[id];

  Uri? artUriForTrack(FathomTrack track) {
    return Uri.parse(
        'content://media/external/audio/media/${track.id}/albumart');
  }

  Future<Uint8List?> _fetchArtwork(int id) async {
    Uint8List? bytes;
    try {
      bytes = await _plugin.queryArtwork(
        id,
        ArtworkType.AUDIO,
        size: 1024,
        quality: 50,
      );
    } catch (_) {}
    if (bytes == null || bytes.isEmpty) {
      try {
        bytes = await fallbackArtFor?.call(id);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null || bytes.isEmpty) return null;
    _artBytes[id] = bytes;
    return bytes;
  }

  void _publishStatus(FathomLibraryStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  /// Publishes the scan saved at the end of the last session.
  ///
  /// The media query is the slow part of a cold start, so the previous list is
  /// painted first and then reconciled. A stale row is corrected by the scan;
  /// losing the file only costs the snapshot, never the library.
  Future<void> restoreSnapshot() async {
    if (_restored) return;
    _restored = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_snapshotName');
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List || _tracks.isNotEmpty) return;

      final tracks = <FathomTrack>[];
      for (final value in raw) {
        final track = FathomTrack.fromJson(value);
        if (track == null || track.origin != TrackOrigin.device) continue;
        if (track.uri.isEmpty) continue;
        tracks.add(track);
      }
      if (tracks.isEmpty || _tracks.isNotEmpty) return;

      _tracks = List.unmodifiable(tracks);
      _status = FathomLibraryStatus.ready;
      _revision++;
      notifyListeners();
    } catch (_) {}
  }

  void _scheduleSnapshot() {
    final tracks = _tracks;
    _snapshotWrite = _snapshotWrite
        .then((_) => _writeSnapshot(tracks))
        .catchError((Object _) {});
  }

  Future<void> _writeSnapshot(List<FathomTrack> tracks) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_snapshotName');
      final temp = File('${file.path}.tmp');
      // A library is thousands of rows; encoding it on the UI isolate is a
      // visible stall right after a scan. The tracks themselves are immutable
      // and cheap to move, so the whole encode runs on a worker.
      await temp.writeAsString(
        await compute(_encodeSnapshot, tracks),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {}
  }

  Future<void> load({required bool grantIfMissing}) async {
    final generation = ++_scanGeneration;
    await restoreSnapshot();

    var granted = false;
    try {
      granted = await OnAudioQuery.platform.permissionsStatus();
    } catch (_) {
      _publishStatus(FathomLibraryStatus.failure);
      return;
    }

    if (!granted) {
      if (!grantIfMissing) {
        _publishStatus(FathomLibraryStatus.permissionNeeded);
        return;
      }
      try {
        granted = await _plugin.checkAndRequest(retryRequest: true);
      } catch (_) {
        granted = false;
      }
      if (!granted) {
        _publishStatus(FathomLibraryStatus.permissionNeeded);
        return;
      }
    }

    // A rescan of an already-ready library is a background refresh. Going
    // through `loading` would hide the list behind a spinner, drop the
    // scroll view (and with it the scroll offset) and make the whole page
    // flash for one arriving file. The status therefore only moves to
    // `loading` when there is no list to keep on screen.
    if (_status != FathomLibraryStatus.ready) {
      _publishStatus(FathomLibraryStatus.loading);
    }

    try {
      final songs = await _plugin.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      if (generation != _scanGeneration) return;
      applyScan(
        songs
            .where((s) => (s.uri ?? '').isNotEmpty)
            .map(FathomTrack.fromDevice)
            .toList(growable: false),
      );
    } catch (_) {
      if (generation != _scanGeneration) return;
      _publishStatus(FathomLibraryStatus.failure);
    }
  }

  /// Deletes the selected device files and rescans what is left.
  ///
  /// The platform owns MediaStore, and on Android 11 and later it may show its
  /// own confirmation for files this app did not create. The native call holds
  /// until that dialog is answered, then returns the media ids that are actually
  /// gone. Only those ids leave the artwork cache; a partial answer is possible
  /// when the user cancels or the provider refuses one row.
  ///
  /// A rescan follows any real deletion, so the list and the selection keys are
  /// reconciled against the store rather than against an optimistic local edit.
  Future<Set<int>> deleteTracks(Iterable<FathomTrack> tracks) async {
    final ids = <int>{
      for (final track in tracks)
        if (track.origin == TrackOrigin.device && track.id >= 0) track.id,
    };
    if (ids.isEmpty) return const {};

    final raw = await _deleteChannel.invokeMethod<List<dynamic>>(
      'deleteTracks',
      {'ids': ids.toList()},
    );
    final deleted = <int>{
      for (final id in raw ?? const <dynamic>[])
        if (id is int && id >= 0) id,
    };
    if (deleted.isEmpty) return deleted;

    for (final id in deleted) {
      _artCache.remove(id);
      _artBytes.remove(id);
    }
    await load(grantIfMissing: false);
    return deleted;
  }

  /// Publishes one scan result.
  ///
  /// An equal scan does nothing at all: no list assignment, no revision bump
  /// and no notification, so an idle rescan cannot rebuild a page. A changed
  /// scan reuses every surviving track instance that did not change its
  /// metadata (see [reconcileLibraryTracks]) and emits exactly one
  /// notification.
  ///
  /// Public for tests; production reaches it through [load], which owns the
  /// storage permission and the media-store query.
  @visibleForTesting
  void applyScan(List<FathomTrack> scanned) {
    final reconciled = reconcileLibraryTracks(_tracks, scanned);
    final statusChanged = _status != FathomLibraryStatus.ready;
    if (reconciled.delta.isEmpty && !statusChanged) {
      // Nothing changed, so the list is not assigned and no notification is
      // emitted. The delta still describes *this* scan, so the record of the
      // previous one is cleared rather than left to look current.
      _delta = FathomLibraryDelta.empty;
      return;
    }

    _tracks = reconciled.tracks;
    _delta = reconciled.delta;
    _revision++;
    _status = FathomLibraryStatus.ready;
    _scheduleSnapshot();
    notifyListeners();
  }
}

/// JSON for the library snapshot.
///
/// Top-level so [compute] can run it on a worker isolate; the list only holds
/// device tracks with a uri, because a remote row has nothing to restore.
String _encodeSnapshot(List<FathomTrack> tracks) => jsonEncode([
      for (final track in tracks)
        if (track.origin == TrackOrigin.device && track.uri.isNotEmpty)
          track.toJson(),
    ]);
