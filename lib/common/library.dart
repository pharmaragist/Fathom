import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/tracks.dart';

enum FathomLibraryStatus { idle, permissionNeeded, loading, ready, failure }

class FathomLibrary extends ChangeNotifier {
  final OnAudioQuery _plugin = OnAudioQuery();
  final Map<int, Future<Uint8List?>> _artCache = {};

  FathomLibraryStatus _status = FathomLibraryStatus.idle;
  List<FathomTrack> _tracks = [];
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
  List<FathomTrack> get tracks => _tracks;

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<Uint8List?> artFor(int id) {
    return _artCache.putIfAbsent(id, () => _fetchArtwork(id));
  }

  Uri? artUriForTrack(FathomTrack track) {
    return Uri.parse('content://media/external/audio/media/${track.id}/albumart');
  }

  Future<Uint8List?> _fetchArtwork(int id) async {
    try {
      return await _plugin.queryArtwork(
        id,
        ArtworkType.AUDIO,
        size: 1024,
        quality: 50,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> load({required bool grantIfMissing}) async {
    var granted = false;
    try {
      granted = await OnAudioQuery.platform.permissionsStatus();
    } catch (_) {
      _status = FathomLibraryStatus.failure;
      notifyListeners();
      return;
    }

    if (!granted) {
      if (!grantIfMissing) {
        _status = FathomLibraryStatus.permissionNeeded;
        notifyListeners();
        return;
      }
      try {
        granted = await _plugin.checkAndRequest(retryRequest: true);
      } catch (_) {
        granted = false;
      }
      if (!granted) {
        _status = FathomLibraryStatus.permissionNeeded;
        notifyListeners();
        return;
      }
    }

    _status = FathomLibraryStatus.loading;
    notifyListeners();

    try {
      final songs = await _plugin.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      _tracks = songs
          .where((s) => (s.uri ?? '').isNotEmpty)
          .map(FathomTrack.fromDevice)
          .toList();
      _status = FathomLibraryStatus.ready;
    } catch (_) {
      _status = FathomLibraryStatus.failure;
    }
    notifyListeners();
  }
}
