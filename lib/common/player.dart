import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracks.dart';
import '../services/audio.dart';
import '../services/equalizer.dart';
import 'constants.dart';
import 'library.dart';
import 'settings.dart';

/// The largest positive band gain in [gains], or zero when every band cuts.
///
/// A coarse upper bound, not a measurement: overlapping bands can sum above it
/// and `DynamicsProcessing` exposes no gain-reduction metering.
double maxEqBoost(Iterable<double> gains) {
  var peak = 0.0;
  for (final gain in gains) {
    if (gain > peak) peak = gain;
  }
  return peak;
}

/// Whether the equalizer has to be applied again for [sessionId].
///
/// An effect belongs to one audio session; when ExoPlayer recreates its session
/// the effect built for the old id accepts gains but processes nothing. A null
/// live id is not a change — the stream reports it once the session exists.
bool eqNeedsApply({
  required bool applied,
  required int? sessionId,
  required int? appliedSessionId,
}) {
  if (!applied) return true;
  return sessionId != null && sessionId != appliedSessionId;
}

/// JSON for the saved queue. Top-level so [compute] can run it off the UI
/// isolate; the payload is a list of immutable tracks plus the selected index.
String _encodeQueueState((List<FathomTrack>, int) state) => jsonEncode({
      'queue': [for (final track in state.$1) track.toJson()],
      'index': state.$2,
    });

/// Decodes a saved payload on a worker. Top-level for the same reason.
Object? _decodeJson(String raw) => jsonDecode(raw);

class FathomPlayer extends ChangeNotifier {
  FathomPlayer(this.settings) {
    _hardwareEqualizer = AndroidEqualizer();
    _audioPlayer = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_hardwareEqualizer]),
    );

    _subscriptions.addAll([
      _audioPlayer.currentIndexStream.listen(_onIndexChanged),
      _audioPlayer.playingStream.listen((playing) {
        _onPlayerStateUpdate();
        // A pause is the last knowable moment before the device sleeps, so the
        // position is written now rather than waiting for the throttle window.
        if (!playing) _flushPosition();
      }),
      _audioPlayer.processingStateStream.listen((_) => _onPlayerStateUpdate()),
      _audioPlayer.androidAudioSessionIdStream
          .distinct()
          .listen((_) => ensureEqReady()),
      _audioPlayer.positionStream.listen((_) => _scheduleStateSave()),
    ]);

    // The lifecycle pause is the last reliable chance to persist the queue:
    // Android may kill a backgrounded process with no further player callbacks.
    _lifecycle = AppLifecycleListener(
      onPause: _flushState,
      onDetach: _flushState,
    );

    _publishMaxEqBoost(_bandGains10());
  }

  final FathomSettings settings;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Largest positive gain across the live ten bands, in decibels; zero for a
  /// flat or cut-only curve.
  ///
  /// A separate notifier so a band drag repaints only the indicator. Only
  /// [_publishMaxEqBoost] writes it, and only on a real change.
  final ValueNotifier<double> maxEqBoostDecibels = ValueNotifier<double>(0.0);

  late final AndroidEqualizer _hardwareEqualizer;
  final FathomNativeEqualizer _nativeEq = FathomNativeEqualizer();
  late final AudioPlayer _audioPlayer;

  FathomAudioHandler? _handler;

  FathomAudioHandler get handler {
    assert(_handler != null,
        'FathomPlayer: AudioService has not been initialized yet.');
    return _handler!;
  }

  List<FathomTrack> _sourceQueue = const [];
  int _selectedIndex = -1;

  bool _eqApplied = false;
  bool _eqReady = false;
  bool _nativeEqReady = false;

  /// The audio session the current equalizer application belongs to.
  ///
  /// The platform destroys an effect with its session; keeping the id beside the
  /// applied state turns that silent loss into a re-attach.
  int? _eqSessionId;

  /// The equalizer application already in flight, if any.
  ///
  /// The audio-session stream can ask twice before the first attach lands;
  /// racing the two lost the native path. One application at a time.
  Future<void>? _eqApplying;
  bool _isSettingQueue = false;
  String _lastError = '';
  Future<void>? _initializeFuture;
  FathomLibrary? _libraryRef;

  /// The pending throttled state write, or null when none is armed.
  ///
  /// A *throttle*, not a debounce: a debounce restarted on every position tick
  /// would never fire. Armed only when none is pending.
  Timer? _saveTimer;

  /// Lifecycle hook that flushes the queue before Android can reclaim the app.
  AppLifecycleListener? _lifecycle;

  /// Whether a restore is currently rebuilding the queue.
  bool _restoring = false;

  bool get shuffle => settings.get<bool>(SettingKey.shuffle);
  FathomRepeatMode get repeatMode => settings.repeatMode;
  List<FathomTrack> get queue => _sourceQueue;
  int get selectedIndex => _selectedIndex;
  bool get hasCurrent =>
      queue.isNotEmpty && _selectedIndex >= 0 && _selectedIndex < queue.length;
  bool get eqReady => _eqReady;
  bool get usingNativeEqualizer => _nativeEqReady;
  String get lastError => _lastError;
  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;
  double get speed => kSpeedFactors[settings.get<int>(SettingKey.speedIndex)];
  FathomTrack? get currentTrack => hasCurrent ? queue[_selectedIndex] : null;

  AudioPlayer get audioPlayer => _audioPlayer;
  AndroidEqualizer get hardwareEqualizer => _hardwareEqualizer;

  /// Whether a skip would actually land on a different track.
  ///
  /// The engine's answer, not a list calculation: shuffle lives inside
  /// just_audio, so `[_selectedIndex + 1]` proves nothing. Also covers
  /// repeat-one and a single-item queue, where "next" == "now".
  bool get canSkipNext {
    if (!hasCurrent) return false;
    final next = _audioPlayer.nextIndex;
    return next != null && next != _audioPlayer.currentIndex;
  }

  bool get canSkipPrevious {
    if (!hasCurrent) return false;
    final previous = _audioPlayer.previousIndex;
    return previous != null && previous != _audioPlayer.currentIndex;
  }

  /// The track a skip would land on, in the engine's play order, or null when
  /// the skip is blocked.
  ///
  /// Deliberately not `queue[_selectedIndex ± 1]`: shuffle never rewrites
  /// [_sourceQueue], so list order and play order differ.
  FathomTrack? get nextTrack => _neighbour(_audioPlayer.nextIndex, canSkipNext);

  FathomTrack? get previousTrack =>
      _neighbour(_audioPlayer.previousIndex, canSkipPrevious);

  FathomTrack? _neighbour(int? index, bool allowed) {
    if (!allowed || index == null || index < 0) return null;
    if (index >= _sourceQueue.length) return null;
    return _sourceQueue[index];
  }

  /// Gives the player the library it reads artwork through.
  ///
  /// A queue restored before the shell mounts has no media item artwork;
  /// republishing here fills it in without waiting for a track change.
  void attachLibrary(FathomLibrary library) {
    _libraryRef = library;
    _pushMediaItem();
  }

  Future<void> initialize() => _initializeFuture ??= _initialize();

  Future<void> _initialize() async {
    await FathomAudioSession.configure();

    try {
      _handler = await AudioService.init<FathomAudioHandler>(
        builder: () => FathomAudioHandler(this),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'pharmaracist.fathom.playback',
          androidNotificationChannelName: 'Fathom Playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('Fathom: audio_service init failed: $e');
    }

    await _audioPlayer.setSpeed(speed);

    // Playback or a restore can land before audio_service has initialized.
    // Without a media item and published state the service is never promoted
    // to the foreground, which Android may kill in the background.
    _pushMediaItem();
    _handler?.sync();
  }

  /// Where the queue, its index and its position are kept.
  ///
  /// Split in two on purpose. The queue is only written when it actually
  /// changes, while the position is written on a timer during playback; a
  /// single payload would rewrite the whole queue — potentially hundreds of
  /// tracks of JSON — every few seconds just to advance one integer. The
  /// position names the track it belongs to, so a stale position can never be
  /// applied to a different track than the one the queue restored.
  ///
  /// The v1 key held one track and its position together; it is still read as a
  /// fallback, and a payload written by this build always lands in v2.
  static const _kQueueKey = 'fathom.player.state.v2';
  static const _kPositionKey = 'fathom.player.position.v2';
  static const _kLegacyStateKey = 'fathom.player.state.v1';

  /// How often the position is persisted while it keeps moving.
  static const _stateInterval = Duration(seconds: 5);

  /// The tail of the serialized state writes.
  ///
  /// Writes are captured in call order and executed one after another: two
  /// snapshots racing on `SharedPreferences` could otherwise land out of order
  /// and restore an older position, and a clear could erase a newer queue.
  Future<void> _stateIo = Future<void>.value();

  /// Arms the next position write if none is pending.
  ///
  /// Deliberately a throttle: the position stream fires several times a second,
  /// and a timer restarted on every tick would never fire, leaving the last
  /// saved position minutes behind the actual one.
  void _scheduleStateSave() {
    if (!hasCurrent || _saveTimer != null) return;
    _saveTimer = Timer(_stateInterval, () {
      _saveTimer = null;
      unawaited(_writePosition());
    });
  }

  /// Persists the live position immediately, leaving the queue as it is.
  void _flushPosition() {
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_writePosition());
  }

  /// Persists the queue, its index and the live position immediately.
  ///
  /// Called where the queue or the current track changes, not on every
  /// position tick: those go through [_scheduleStateSave].
  void _flushState() {
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_writeQueue());
    unawaited(_writePosition());
  }

  /// Stores the queue and the index of the track it was playing.
  Future<void> _writeQueue() {
    if (!hasCurrent) return Future<void>.value();
    // Snapshot before queueing: `dispose` calls this and then tears the player
    // down before the queued task gets to run. Shuffle and repeat are settings,
    // not queue state: they are written on every toggle, so they are always at
    // least as fresh as this payload. The encode itself runs on a worker: a
    // full queue can be thousands of rows, and JSON encoding it on the UI
    // isolate is a stall every time the queue is edited.
    final queue = List<FathomTrack>.of(_sourceQueue);
    final index = _selectedIndex;
    return _stateIo = _stateIo.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _kQueueKey,
          await compute(_encodeQueueState, (queue, index)),
        );
      } catch (_) {}
    });
  }

  /// Stores where the current track stopped, tagged with its id.
  Future<void> _writePosition() {
    if (!hasCurrent) return Future<void>.value();
    final track = currentTrack!;
    final data = {
      'id': track.id,
      'positionMs': _audioPlayer.position.inMilliseconds,
    };
    return _stateIo = _stateIo.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kPositionKey, jsonEncode(data));
      } catch (_) {}
    });
  }

  /// Drops the saved state after the queue has deliberately become empty.
  ///
  /// Not folded into [_writeQueue]: an empty player is also what boot looks
  /// like before the restore lands, and clearing on every empty flush would
  /// erase the very payload being restored. Only an explicit structural edit
  /// calls this.
  Future<void> _clearState() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _stateIo = _stateIo.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kQueueKey);
        await prefs.remove(_kPositionKey);
        await prefs.remove(_kLegacyStateKey);
      } catch (_) {}
    });
  }

  /// The saved position for [current], or zero when it belongs to another track.
  ///
  /// The id guard is what makes splitting the keys safe: the position is
  /// written on a timer, the queue only on structural changes, so the two can
  /// describe different moments. A position tagged with a track that is not the
  /// one the queue restored is stale and is discarded rather than seeked to.
  Duration _savedPosition(
    SharedPreferences prefs,
    Map<dynamic, dynamic> queuePayload,
    FathomTrack current,
  ) {
    final raw = prefs.getString(_kPositionKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['id'] == current.id) {
          final ms = decoded['positionMs'];
          if (ms is int && ms > 0) return Duration(milliseconds: ms);
        }
      } catch (_) {}
      return Duration.zero;
    }

    // v1 kept the position beside the single track it belonged to.
    if (queuePayload['id'] == current.id) {
      final ms = queuePayload['positionMs'];
      if (ms is int && ms > 0) return Duration(milliseconds: ms);
    }
    return Duration.zero;
  }

  /// Rebuilds the last queue and seeks to where it stopped, playing nothing.
  ///
  /// Runs after [initialize], so the handler and the engine are ready. Restoring
  /// the whole queue rather than the current track is what keeps "next" working
  /// after a cold start: the engine's source list and [queue] stay index-aligned,
  /// exactly as they were when [playFrom] built them.
  Future<void> restoreLastState() async {
    if (_restoring) return;
    _restoring = true;
    var loaded = false;
    try {
      // A user who started something while boot was still running owns the
      // player now; restoring over it would yank the queue out from under them.
      if (hasCurrent) return;

      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString(_kQueueKey) ?? prefs.getString(_kLegacyStateKey);
      if (raw == null) return;
      final decoded = await compute(_decodeJson, raw);
      if (decoded is! Map) return;

      final tracks = <FathomTrack>[];
      final savedQueue = decoded['queue'];
      if (savedQueue is List) {
        for (final entry in savedQueue) {
          final track = FathomTrack.fromJson(entry);
          if (track != null &&
              track.origin == TrackOrigin.device &&
              track.uri.isNotEmpty) {
            tracks.add(track);
          }
        }
      } else {
        // v1: the payload was one track at the top level.
        final track = FathomTrack.fromJson(decoded);
        if (track != null &&
            track.origin == TrackOrigin.device &&
            track.uri.isNotEmpty) {
          tracks.add(track);
        }
      }
      if (tracks.isEmpty) return;

      final rawIndex = decoded['index'];
      final index =
          (rawIndex is int ? rawIndex : 0).clamp(0, tracks.length - 1);
      final position = _savedPosition(prefs, decoded, tracks[index]);

      _sourceQueue = tracks;
      _selectedIndex = index;
      _isSettingQueue = true;
      notifyListeners();
      try {
        await _audioPlayer.setAudioSources(
          [
            for (final track in tracks)
              AudioSource.uri(Uri.parse(track.uri), tag: track.id),
          ],
          initialIndex: index,
          initialPosition: position,
        );
        loaded = true;
        await _audioPlayer.setShuffleModeEnabled(shuffle);
        await _audioPlayer.setLoopMode(_loopModeFor(repeatMode));
      } finally {
        _isSettingQueue = false;
      }
      _pushMediaItem();
      _handler?.sync();
      notifyListeners();
    } catch (_) {
      // The saved file may have been deleted outside Fathom, or the media
      // store may have re-indexed it. Never leave a queue whose sources the
      // engine refused: the UI would show a current track that cannot play.
      if (!loaded) {
        _sourceQueue = const [];
        _selectedIndex = -1;
        // Retrying a queue the engine already refused would fail the same way
        // on every cold start; the state file is the thing to drop.
        unawaited(_clearState());
      }
      _isSettingQueue = false;
      notifyListeners();
    } finally {
      _restoring = false;
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    // Snapshot before the player is torn down; `_flushState` reads the queue
    // and position synchronously before its first await.
    _flushState();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    maxEqBoostDecibels.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Turns tracks into playable sources.
  ///
  /// Every playable track is a file on this device: a YouTube Music item is
  /// downloaded before it can be played, at which point the library scan finds
  /// it and it arrives here as a device track. A track that is still remote
  /// has nothing to play, so it is dropped — the player's queue and just_audio's
  /// sources must stay index-aligned.
  Future<(List<FathomTrack>, List<AudioSource>)> _resolveAll(
    List<FathomTrack> tracks,
  ) async {
    final playable = <FathomTrack>[];
    final sources = <AudioSource>[];
    for (final track in tracks) {
      if (track.origin != TrackOrigin.device) continue;
      playable.add(track);
      sources.add(AudioSource.uri(Uri.parse(track.uri), tag: track.id));
    }
    return (playable, sources);
  }

  Future<bool> playFrom(List<FathomTrack> list, int index) async {
    if (list.isEmpty || index < 0 || index >= list.length) return false;

    try {
      final (playable, sources) = await _resolveAll(list);

      if (sources.isEmpty) {
        _lastError = 'Nothing here is downloaded yet';
        notifyListeners();
        return false;
      }

      final newIndex = playable.indexWhere((t) => t == list[index]);
      if (newIndex < 0) {
        _lastError = 'Download this track before playing it';
        notifyListeners();
        return false;
      }

      _sourceQueue = playable;
      _selectedIndex = newIndex;
      _isSettingQueue = true;
      notifyListeners();

      await _audioPlayer.setAudioSources(
        sources,
        initialIndex: newIndex,
        initialPosition: Duration.zero,
      );

      await _audioPlayer.setShuffleModeEnabled(shuffle);
      await _audioPlayer.setLoopMode(_loopModeFor(repeatMode));

      _isSettingQueue = false;
      _pushMediaItem();
      _flushState();
      unawaited(_startPlayback());
      return true;
    } catch (e) {
      _isSettingQueue = false;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> playIndex(int index) async {
    if (index < 0 || index >= queue.length) return;
    _selectedIndex = index;

    try {
      await _audioPlayer.seek(Duration.zero, index: index);
      _pushMediaItem();
      _flushState();
      unawaited(_startPlayback());
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Adds tracks to the end of the queue, playing nothing new.
  Future<bool> enqueue(List<FathomTrack> tracks) =>
      _insert(tracks, next: false);

  /// Puts tracks immediately after the current one.
  Future<bool> playNext(List<FathomTrack> tracks) =>
      _insert(tracks, next: true);

  Future<bool> _insert(List<FathomTrack> tracks, {required bool next}) async {
    if (tracks.isEmpty) return false;
    if (!hasCurrent) return playFrom(tracks, 0);

    try {
      final current = _audioPlayer.currentIndex ?? _selectedIndex;
      final currentTrack = _sourceQueue[current];
      final cut = next ? current + 1 : _sourceQueue.length;
      final rebuilt = [
        ..._sourceQueue.sublist(0, cut),
        ...tracks,
        ..._sourceQueue.sublist(cut),
      ];

      final (playable, sources) = await _resolveAll(rebuilt);
      if (sources.isEmpty) return false;

      _sourceQueue = playable;
      // The current track keeps playing; re-find it in the rebuilt list.
      final kept = playable.indexOf(currentTrack);
      _selectedIndex = kept < 0 ? 0 : kept;
      _isSettingQueue = true;
      notifyListeners();

      await _audioPlayer.setAudioSources(
        sources,
        initialIndex: _selectedIndex,
        initialPosition: _audioPlayer.position,
      );
      await _audioPlayer.setShuffleModeEnabled(shuffle);
      await _audioPlayer.setLoopMode(_loopModeFor(repeatMode));

      _isSettingQueue = false;
      _pushMediaItem();
      _flushState();
      return true;
    } catch (e) {
      _isSettingQueue = false;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _sourceQueue.length) return;
    _sourceQueue = List.of(_sourceQueue)..removeAt(index);

    if (_sourceQueue.isEmpty) {
      _selectedIndex = -1;
    } else if (index < _selectedIndex) {
      _selectedIndex -= 1;
    }

    await _rebuildSources();
    _pushMediaItem();
    _handler?.sync();
  }

  /// Moves one queue item to another position.
  ///
  /// `to` is the index inside the list that remains after `from` is removed,
  /// which is what the reorder callback hands over.
  Future<void> moveAt(int from, int to) async {
    if (from < 0 || from >= _sourceQueue.length) return;
    if (to < 0 || to >= _sourceQueue.length) return;
    if (from == to) return;

    final wasSelected = _selectedIndex;
    _sourceQueue = List.of(_sourceQueue);
    final track = _sourceQueue.removeAt(from);
    _sourceQueue.insert(to, track);

    if (wasSelected == from) {
      _selectedIndex = to;
    } else if (from < wasSelected && wasSelected <= to) {
      _selectedIndex = wasSelected - 1;
    } else if (to <= wasSelected && wasSelected < from) {
      _selectedIndex = wasSelected + 1;
    }

    await _rebuildSources();
    _pushMediaItem();
    _handler?.sync();
  }

  /// Removes deleted files from the queue without touching the library.
  ///
  /// Deletion can land on a queued track or on the one playing. A current
  /// track that is gone stops rather than seeking into whatever takes its
  /// place, and the next surviving row becomes current but stays paused. A
  /// deletion elsewhere in the queue keeps the current position and playback
  /// state, because nothing the user is listening to changed.
  Future<void> forgetTracks(Set<int> mediaIds) async {
    if (mediaIds.isEmpty || _sourceQueue.isEmpty) return;

    final current = currentTrack;
    final removedCurrent = current != null && mediaIds.contains(current.id);
    final nextQueue = [
      for (final track in _sourceQueue)
        if (!mediaIds.contains(track.id)) track,
    ];
    if (nextQueue.length == _sourceQueue.length) return;

    if (nextQueue.isEmpty) {
      _isSettingQueue = true;
      notifyListeners();
      await _audioPlayer.stop();
      await _audioPlayer.setAudioSources(const []);
      _sourceQueue = const [];
      _selectedIndex = -1;
      _isSettingQueue = false;
      _handler?.mediaItem.add(null);
      _handler?.sync();
      notifyListeners();
      unawaited(_clearState());
      return;
    }

    if (current == null) {
      _sourceQueue = nextQueue;
      _selectedIndex = -1;
      notifyListeners();
      _flushState();
      return;
    }

    if (removedCurrent) {
      final oldIndex = _selectedIndex;
      _sourceQueue = nextQueue;
      _selectedIndex = oldIndex.clamp(0, nextQueue.length - 1);
      await _audioPlayer.stop();
      await _rebuildSources(
        position: Duration.zero,
        resume: false,
      );
    } else {
      final kept = nextQueue.indexOf(current);
      _sourceQueue = nextQueue;
      _selectedIndex = kept < 0 ? 0 : kept;
      await _rebuildSources();
    }
    _pushMediaItem();
    _handler?.sync();
  }

  /// Replays the queue into the audio player without changing what is heard.
  ///
  /// just_audio holds its own copy of the sources, so every structural edit
  /// made to [queue] has to be reflected here or the two lists drift apart and
  /// the wrong track plays next.
  ///
  /// [position] and [resume] let a caller that is deliberately changing what is
  /// heard — deleting the current track — start the replacement at zero and
  /// stay paused, instead of inheriting the old track's position and play
  /// state.
  Future<void> _rebuildSources({Duration? position, bool? resume}) async {
    if (_sourceQueue.isEmpty) {
      _isSettingQueue = true;
      notifyListeners();
      await _audioPlayer.setAudioSources(const []);
      _isSettingQueue = false;
      notifyListeners();
      unawaited(_clearState());
      return;
    }

    final index = _selectedIndex.clamp(0, _sourceQueue.length - 1);
    final startPosition = position ?? _audioPlayer.position;
    final wasPlaying = resume ?? _audioPlayer.playing;

    try {
      _isSettingQueue = true;
      notifyListeners();

      final (playable, sources) = await _resolveAll(_sourceQueue);
      _sourceQueue = playable;
      _selectedIndex = index.clamp(0, playable.length - 1);

      await _audioPlayer.setAudioSources(
        sources,
        initialIndex: _selectedIndex,
        initialPosition: startPosition,
      );
      await _audioPlayer.setShuffleModeEnabled(shuffle);
      await _audioPlayer.setLoopMode(_loopModeFor(repeatMode));
      if (wasPlaying) await _audioPlayer.play();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isSettingQueue = false;
      notifyListeners();
      _flushState();
    }
  }

  Future<void> playNow() => _audioPlayer.play();
  void pauseNow() => _audioPlayer.pause();

  void stopAll() {
    _audioPlayer.stop();
    _handler?.sync();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_audioPlayer.playing) {
      pauseNow();
    } else {
      await playNow();
    }
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (canSkipNext) await _audioPlayer.seekToNext();
  }

  Future<void> skipPrevious() async {
    if (_audioPlayer.position > const Duration(seconds: 3)) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }
    if (canSkipPrevious) await _audioPlayer.seekToPrevious();
  }

  Future<void> seekTo(Duration position) async {
    await _audioPlayer.seek(position);
    _handler?.sync();
    notifyListeners();
    // A seek is a deliberate position the user chose; waiting for the throttle
    // would lose it if the app died in the next few seconds. The queue did not
    // change, so only the small position key is rewritten.
    _flushPosition();
  }

  Future<void> seekBy(int seconds) async {
    final target = _audioPlayer.position + Duration(seconds: seconds);
    final max = duration ?? const Duration(hours: 1);
    final clamped =
        target < Duration.zero ? Duration.zero : (target > max ? max : target);
    await _audioPlayer.seek(clamped);
    _handler?.sync();
    _flushPosition();
  }

  Future<void> setSpeedFactor(double factor) async {
    await _audioPlayer.setSpeed(factor);
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    final next = !shuffle;
    settings.set(SettingKey.shuffle, next);
    await _audioPlayer.setShuffleModeEnabled(next);
    _handler?.sync();
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    final nextIndex = (settings.get<int>(SettingKey.repeatIndex) + 1) %
        FathomRepeatMode.values.length;
    settings.set(SettingKey.repeatIndex, nextIndex);
    await _audioPlayer.setLoopMode(_loopModeFor(repeatMode));
    _handler?.sync();
    notifyListeners();
  }

  LoopMode _loopModeFor(FathomRepeatMode mode) => switch (mode) {
        FathomRepeatMode.off => LoopMode.off,
        FathomRepeatMode.all => LoopMode.all,
        FathomRepeatMode.one => LoopMode.one,
      };

  Future<void> ensureEqReady({bool force = false}) async {
    if (force) {
      // A forced check is what a visible equalizer surface uses: the effect can
      // survive its audio session without the session id changing, so the only
      // reliable answer is to build it again on the live session.
      _eqApplied = false;
      _eqSessionId = null;
    } else if (_nativeEqReady && !await _nativeEq.isAlive()) {
      _nativeEqReady = false;
      _eqApplied = false;
      _eqSessionId = null;
    }
    await _tryApplyEqualizer();
  }

  /// The latest gain per band that the native stage has not accepted yet.
  ///
  /// A band drag produces far more events than the effect can take. Keeping
  /// only the newest value per band and letting one writer drain the map bounds
  /// the channel traffic without making the dial lag behind the finger.
  final Map<int, double> _pendingGains = {};
  Future<void>? _gainWriter;
  double? _pendingPreamp;
  Future<void>? _preampWriter;

  void setBandGain(int centerHz, double db, {bool persist = false}) {
    // Stage before writing: a recovery replays the stored curve, so the newest
    // value has to be in the model before the write can be refused.
    settings.stageEqGain(centerHz, db);
    if (settings.get<String?>(SettingKey.eqPreset) != null) {
      settings.set<String?>(SettingKey.eqPreset, null);
    }
    unawaited(_setBandGain(centerHz, db));
    if (persist) settings.commitEq();
    _publishMaxEqBoost(_bandGains10());
  }

  /// Sets the preamp (input gain) used by the native equalizer, in decibels.
  ///
  /// The hardware fallback has no preamp stage, so this is a no-op there.
  void setPreamp(double db, {bool persist = false}) {
    final clamped = db.clamp(-FathomNativeEqualizer.maxPreampDecibels,
        FathomNativeEqualizer.maxPreampDecibels);
    settings.stageEqPreamp(clamped);
    if (_nativeEqReady) {
      _pendingPreamp = clamped;
      unawaited(_drainPreamp());
    }
    if (persist) settings.commitEq();
  }

  /// Enables or bypasses the native soft peak limiter.
  ///
  /// The limiter is a safety net after preamp and EQ, not a loudness stage: it
  /// only reduces gain when the processed signal approaches full scale. The
  /// setting notifies on its own, so this deliberately does not.
  void setLimiter(bool enabled) {
    settings.set<bool>(SettingKey.limiter, enabled);
    if (_nativeEqReady) unawaited(_nativeEq.setLimiter(enabled));
  }

  /// Writes [maxEqBoostDecibels] only when the peak actually moved.
  ///
  /// Called from every path that stages, applies or replaces band gains. It
  /// never calls `notifyListeners()`: the indicator listens to the notifier
  /// itself, and a player-wide rebuild per band tick would be wasted work.
  void _publishMaxEqBoost(Iterable<double> gains) {
    final peak = maxEqBoost(gains);
    if (maxEqBoostDecibels.value != peak) maxEqBoostDecibels.value = peak;
  }

  Future<void> _setBandGain(int centerHz, double db) {
    if (_nativeEqReady) {
      final idx = kEq10Bands.indexOf(centerHz);
      if (idx >= 0) {
        final clamped = db.clamp(
          FathomNativeEqualizer.minDecibels,
          FathomNativeEqualizer.maxDecibels,
        );
        _pendingGains[idx] = clamped;
        return _drainBandGains();
      }
    }
    return _setBandOnDevice(centerHz, db);
  }

  /// Serialises native band writes, newest value per band.
  Future<void> _drainBandGains() {
    return _gainWriter ??=
        _runBandGainWriter().whenComplete(() => _gainWriter = null);
  }

  Future<void> _runBandGainWriter() async {
    var recovered = false;
    while (_pendingGains.isNotEmpty) {
      if (!_nativeEqReady) {
        // The effect was replaced by the hardware fallback; the curve is
        // already staged and the hardware path owns it from here.
        _pendingGains.clear();
        return;
      }
      final index = _pendingGains.keys.first;
      final db = _pendingGains.remove(index)!;
      if (await _nativeEq.setGain(index, db)) continue;

      // The engine refused the write: rebuild it on the live session, which
      // replays the stored curve — including this value, because it was staged
      // before the write. One recovery attempt per drain is enough; a second
      // refusal means the device will not accept this session at all.
      if (recovered) {
        _pendingGains.clear();
        return;
      }
      recovered = true;
      await _recoverNativeEqualizer();
    }
  }

  Future<void> _drainPreamp() {
    return _preampWriter ??=
        _runPreampWriter().whenComplete(() => _preampWriter = null);
  }

  Future<void> _runPreampWriter() async {
    var recovered = false;
    while (_pendingPreamp != null) {
      if (!_nativeEqReady) {
        _pendingPreamp = null;
        return;
      }
      final db = _pendingPreamp!;
      _pendingPreamp = null;
      if (await _nativeEq.setPreamp(db)) continue;
      if (recovered) return;
      recovered = true;
      await _recoverNativeEqualizer();
    }
  }

  /// Rebuilds the native effect on the live audio session and replays the
  /// stored curve. Called after a write was refused, never on the happy path.
  Future<void> _recoverNativeEqualizer() async {
    _nativeEqReady = false;
    _eqApplied = false;
    _eqSessionId = null;
    await _tryApplyEqualizer();
    notifyListeners();
  }

  Future<void> applyEqPreset(String preset) async {
    final presetGains = _presetGains(preset);
    if (presetGains == null) return;

    settings.set<String?>(SettingKey.eqPreset, preset);

    final preamp = settings.eqPresetFor(preset)?.preamp;
    if (preamp != null) settings.stageEqPreamp(preamp);

    if (!_eqReady) {
      if (preamp != null) {
        settings.stageEqPreamp(preamp);
        settings.commitEq();
      }
      _publishMaxEqBoost(_bandGains10());
      notifyListeners();
      return;
    }

    try {
      if (_nativeEqReady) {
        final target = List<double>.generate(kEq10Bands.length, (i) {
          final db = presetGains[i];
          final clamped = db.clamp(
            FathomNativeEqualizer.minDecibels,
            FathomNativeEqualizer.maxDecibels,
          );
          return clamped;
        });
        // Stage before writing: the recovery path replays the stored curve, so
        // the preset has to be in the model before a refusal can drop the call.
        for (var i = 0; i < kEq10Bands.length; i++) {
          settings.stageEqGain(kEq10Bands[i], target[i]);
        }
        if (!await _nativeEq.setGains(target)) {
          await _recoverNativeEqualizer();
        } else if (preamp != null) {
          await _nativeEq.setPreamp(preamp);
        }
      } else {
        final params = await _hardwareEqualizer.parameters;
        for (final band in params.bands) {
          final hz = band.centerFrequency.toInt();
          final idx = kEq10Bands.indexOf(hz);
          final db = idx != -1 ? presetGains[idx] : 0.0;
          final clamped =
              db.clamp(params.minDecibels, params.maxDecibels).toDouble();
          await band.setGain(clamped);
          settings.stageEqGain(hz, clamped);
        }
      }
      settings.commitEq();
    } catch (_) {}
    _publishMaxEqBoost(_bandGains10());
    notifyListeners();
  }

  /// The live ten band gains in [kEq10Bands] order, favouring explicit band
  /// overrides and falling back to the selected preset.
  List<double> _bandGains10() {
    final gains = settings.eqGains;
    final presetGains =
        _presetGains(settings.get<String?>(SettingKey.eqPreset));
    return [
      for (var i = 0; i < kEq10Bands.length; i++)
        gains[kEq10Bands[i]] ?? presetGains?[i] ?? 0.0,
    ];
  }

  /// Saves the live curve under [name] and selects it.
  ///
  /// Pass [replacing] to rename an existing preset instead of adding one.
  void saveEqPreset(String name, {String? replacing}) {
    settings.saveEqPreset(
      name,
      EqPreset(gains: _bandGains10(), preamp: settings.eqPreamp),
      replacing: replacing,
    );
    settings.set<String?>(SettingKey.eqPreset, name);
  }

  /// Stores the imported [preset] under [name] and makes it the active curve.
  ///
  /// Used by the AutoEQ browser, which supplies a curve it fetched rather than
  /// reading the live one.
  void addEqPreset(String name, EqPreset preset) {
    settings.saveEqPreset(name, preset);
    unawaited(applyEqPreset(name));
  }

  /// Deletes the preset [name], clearing the selection when it was active.
  void deleteEqPreset(String name) {
    settings.removeEqPreset(name);
    if (settings.get<String?>(SettingKey.eqPreset) == name) {
      settings.set<String?>(SettingKey.eqPreset, null);
    }
    _publishMaxEqBoost(_bandGains10());
  }

  /// Band gains for [preset] in [kEq10Bands] order, or null when unknown.
  List<double>? _presetGains(String? preset) {
    if (preset == null) return null;
    final def = settings.eqPresetFor(preset);
    return def?.gains;
  }

  Future<void> setDeviceEqualizerEnabled(bool enabled) async {
    settings.set(SettingKey.eqEnabled, enabled);
    if (_nativeEqReady) {
      // The reapply reads `eqEnabled` from the model, so the recovery is the
      // retry: there is no separate second write to make.
      if (!await _nativeEq.setEnabled(enabled)) {
        await _recoverNativeEqualizer();
      }
      return;
    }
    if (!_eqReady) return;
    try {
      await _hardwareEqualizer.setEnabled(enabled);
    } catch (_) {}
  }

  Future<void> _setBandOnDevice(int centerHz, double db) async {
    if (!_eqReady || _nativeEqReady) return;
    try {
      final params = await _hardwareEqualizer.parameters;
      for (final band in params.bands) {
        if (band.centerFrequency.toInt() == centerHz) {
          final clamped =
              db.clamp(params.minDecibels, params.maxDecibels).toDouble();
          await band.setGain(clamped);
        }
      }
    } catch (_) {}
  }

  Future<void> _tryApplyEqualizer() {
    final sessionId = _audioPlayer.androidAudioSessionId;
    // A different session id means the effect was built on a session the
    // platform has since destroyed, so `_eqApplied` describes an effect that
    // no longer hears anything. Re-apply rather than trusting the latch.
    final needsApply = eqNeedsApply(
      applied: _eqApplied,
      sessionId: sessionId,
      appliedSessionId: _eqSessionId,
    );
    if (!needsApply) return Future<void>.value();
    final sessionChanged = sessionId != null && sessionId != _eqSessionId;

    final inFlight = _eqApplying;
    if (inFlight == null) {
      return _eqApplying = _applyEqualizer().whenComplete(() {
        _eqApplying = null;
      });
    }
    // An application is already running. If it started before the session
    // changed, it is attaching to the dead id: run again once it finishes
    // instead of dropping the update.
    if (!sessionChanged) return inFlight;
    return inFlight.then((_) => _tryApplyEqualizer());
  }

  Future<void> _applyEqualizer() async {
    final sessionId = _audioPlayer.androidAudioSessionId;
    if (!await _nativeEq.isSupported()) {
      await _applyHardwareEqualizer(sessionId);
      return;
    }
    if (sessionId == null) {
      // The audio session is only created once a track loads, so retry then
      // (see the `androidAudioSessionIdStream` subscription in the constructor).
      return;
    }

    _nativeEqReady = false;
    try {
      final attached = await _nativeEq.attach(
        sessionId: sessionId,
        bands: List<int>.of(kEq10Bands),
        preamp: settings.eqPreamp,
        limiter: settings.get<bool>(SettingKey.limiter),
      );
      if (attached) {
        _nativeEqReady = true;
        _eqApplied = true;
        _eqSessionId = sessionId;
        if (await _applyNativeEqualizer()) {
          _eqReady = true;
          notifyListeners();
          return;
        }
        // The engine exists but refused the curve, so it is not a usable
        // stage: release it and take the hardware path rather than leaving
        // dials wired to an effect that answers nothing.
        _nativeEqReady = false;
        await _nativeEq.detach();
      }
    } catch (_) {
      await _nativeEq.detach();
      _eqSessionId = null;
    }

    await _applyHardwareEqualizer(sessionId);
  }

  Future<void> _applyHardwareEqualizer(int? sessionId) async {
    try {
      final params = await _hardwareEqualizer.parameters;
      _eqReady = true;

      final gains = settings.eqGains;
      final preset = settings.get<String?>(SettingKey.eqPreset);
      final presetGains = _presetGains(preset);

      for (final band in params.bands) {
        final hz = band.centerFrequency.toInt();
        double? db = gains[hz];

        if (db == null && presetGains != null) {
          final idx = kEq10Bands.indexOf(hz);
          if (idx != -1) db = presetGains[idx];
        }

        if (db != null) {
          final clamped =
              db.clamp(params.minDecibels, params.maxDecibels).toDouble();
          await band.setGain(clamped);
        }
      }
      await _hardwareEqualizer
          .setEnabled(settings.get<bool>(SettingKey.eqEnabled));
      // The hardware fallback may expose fewer bands than the ten the app
      // stores, so it cannot itself describe the requested curve. The limiter
      // predicts from the curve the user actually asked for, not from whatever
      // the device could reproduce.
      _publishMaxEqBoost(_bandGains10());
      _eqApplied = true;
      // The fallback belongs to this session too: just_audio rebuilds its
      // effects on the same signal, and the gains have to be pushed again.
      _eqSessionId = sessionId;
    } catch (_) {
      _eqReady = false;
      _eqApplied = false;
    }
    notifyListeners();
  }

  Future<bool> _applyNativeEqualizer() async {
    if (!_nativeEqReady) return false;
    final gains = settings.eqGains;
    final preset = settings.get<String?>(SettingKey.eqPreset);
    final presetGains = _presetGains(preset);

    final target = List<double>.generate(kEq10Bands.length, (i) {
      final hz = kEq10Bands[i];
      double? db = gains[hz];
      if (db == null && presetGains != null) db = presetGains[i];
      db ??= 0.0;
      final clamped = db.clamp(
        FathomNativeEqualizer.minDecibels,
        FathomNativeEqualizer.maxDecibels,
      );
      return clamped;
    });
    _publishMaxEqBoost(target);

    // Short-circuit: a refused write already means the stage is unusable, and
    // the caller has to fall back instead of sending the rest of the curve.
    final ok = await _nativeEq.setGains(target) &&
        await _nativeEq.setPreamp(settings.eqPreamp) &&
        await _nativeEq.setEnabled(settings.get<bool>(SettingKey.eqEnabled)) &&
        await _nativeEq.setLimiter(settings.get<bool>(SettingKey.limiter));
    if (ok) {
      // The full curve was just written, so anything the drag queued while the
      // reapply ran is already represented in it.
      _pendingGains.clear();
      _pendingPreamp = null;
    }
    return ok;
  }

  Future<void> _startPlayback() async {
    try {
      unawaited(_tryApplyEqualizer());
      await _audioPlayer.play();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _onIndexChanged(int? idx) {
    if (_isSettingQueue || idx == null) return;
    if (idx == _selectedIndex) return;

    _selectedIndex = idx;
    _pushMediaItem();
    _handler?.sync();
    notifyListeners();
    _flushState();
  }

  void _onPlayerStateUpdate() {
    _handler?.sync();
    notifyListeners();
  }

  MediaItem _mediaItemFor(FathomTrack t) {
    // A remote track has no uri yet, so its identity for the notification is
    // the videoId.
    final id = t.origin == TrackOrigin.ytMusic ? 'yt:${t.videoId}' : t.uri;
    final artUri = t.origin == TrackOrigin.ytMusic
        ? t.thumbUri
        : _libraryRef?.artUriForTrack(t);
    return MediaItem(
      id: id,
      title: t.title,
      artist: t.artist,
      duration:
          t.durationMs == null ? null : Duration(milliseconds: t.durationMs!),
      artUri: artUri,
    );
  }

  void _pushMediaItem() {
    if (hasCurrent && _handler != null) {
      _handler!.mediaItem.add(_mediaItemFor(currentTrack!));
    }
  }
}
