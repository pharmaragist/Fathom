import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppName = 'Fathom';
const String kAppCreator = 'pharmaracist';
const String kAppSubtitle = 'by $kAppCreator';
const String kAppVersion = '1.0.0';

const List<Color> kAccentSwatches = [
  Color(0xFFFFFFFF),
  Color(0xFF0A84FF),
  Color(0xFF64D2FF),
  Color(0xFF30D158),
  Color(0xFFFFD60A),
  Color(0xFFFF9F0A),
  Color(0xFFFF453A),
  Color(0xFFBF5AF2),
  Color(0xFFFF2D55),
];

const double kBottomNavWidth = 305.0;
const List<String> kFontOptions = ['System', 'Oswald'];

const List<double> kSpeedFactors = [0.5, 1.0, 1.25, 1.5, 2.0];
const List<String> kSpeedLabels = ['0.5x', '1x', '1.25x', '1.5x', '2x'];

const List<int> kEq10Bands = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const List<String> kEqPresets = [
  'Flat',
  'Bass Boost',
  'Vocal Boost',
  'Rock',
  'Electronic'
];

const Map<String, List<double>> kEqPresetGains10 = {
  'Flat': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  'Bass Boost': [7.0, 6.0, 5.0, 3.0, 1.0, 0.0, -1.0, -1.5, -2.0, -2.0],
  'Vocal Boost': [-1.0, -0.5, 0.0, 1.5, 3.0, 3.5, 2.5, 1.0, 0.0, -1.0],
  'Rock': [5.0, 4.0, 3.0, 1.5, -0.5, -0.5, 1.0, 2.5, 3.5, 4.5],
  'Electronic': [6.0, 5.5, 4.0, 2.0, 0.0, -1.0, 0.5, 2.0, 3.5, 4.0],
};

String formatDuration(Duration d) {
  final min = d.inMinutes;
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$min:$sec';
}

String frequencyLabel(int hz) {
  if (hz >= 1000) {
    final k = hz / 1000.0;
    return k == k.roundToDouble()
        ? '${k.toInt()}k'
        : '${k.toStringAsFixed(1)}k';
  }
  return '$hz';
}

enum FathomRepeatMode { off, all, one }

class FathomTrack {
  final int id;
  final String title;
  final String artist;
  final String uri;
  final int? dateAdded;
  final int? durationMs;

  const FathomTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    required this.durationMs,
    this.dateAdded,
  });

  factory FathomTrack.fromDevice(dynamic song) {
    final uri = (song.uri as String?) ?? '';
    final artist = (song.artist as String?);
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

  factory FathomTrack.fromMap(Map<String, Object?> m) => FathomTrack(
        id: (m['id'] as num?)?.toInt() ?? 0,
        title: (m['title'] as String?) ?? 'Untitled',
        artist: (m['artist'] as String?) ?? 'Unknown Artist',
        uri: (m['uri'] as String?) ?? '',
        durationMs: (m['duration'] as num?)?.toInt(),
        dateAdded: (m['dateAdded'] as num?)?.toInt(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'uri': uri,
        'duration': durationMs,
        'dateAdded': dateAdded,
      };

  @override
  bool operator ==(Object other) => other is FathomTrack && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

class FathomSettings extends ChangeNotifier {
  FathomSettings._(
    this._prefs, {
    required int accentIndex,
    required bool useArtAccent,
    required String fontKey,
    required bool gapless,
    required int speedIndex,
    required int sortIndex,
    required bool eqEnabled,
    required String? eqPreset,
    required Map<int, double> eqGains,
    required bool shuffle,
    required int repeatIndex,
  })  : _accentIndex = accentIndex.clamp(0, kAccentSwatches.length - 1).toInt(),
        _useArtAccent = useArtAccent,
        _fontKey = fontKey,
        _gapless = gapless,
        _speedIndex = speedIndex.clamp(0, kSpeedFactors.length - 1).toInt(),
        _sortIndex = sortIndex,
        _eqEnabled = eqEnabled,
        _eqPreset = eqPreset,
        _eqGains = eqGains,
        _shuffle = shuffle,
        _repeatIndex =
            repeatIndex.clamp(0, FathomRepeatMode.values.length - 1).toInt();

  final SharedPreferences _prefs;

  int _accentIndex;
  bool _useArtAccent;
  Color? _extractedArtAccent;
  String _fontKey;
  bool _gapless;
  int _speedIndex;
  int _sortIndex;
  bool _eqEnabled;
  String? _eqPreset;
  final Map<int, double> _eqGains;
  bool _shuffle;
  int _repeatIndex;

  static const _kAccent = 'fathom.accent';
  static const _kUseArtAccent = 'fathom.art_accent';
  static const _kFont = 'fathom.font';
  static const _kGapless = 'fathom.gapless';
  static const _kSpeed = 'fathom.speed';
  static const _kSort = 'fathom.sort';
  static const _kEqEnabled = 'fathom.eq.enabled';
  static const _kEqPreset = 'fathom.eq.preset';
  static const _kEqGains = 'fathom.eq.gains';
  static const _kQueue = 'fathom.queue';
  static const _kShuffle = 'fathom.shuffle';
  static const _kRepeat = 'fathom.repeat';

  static Future<FathomSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kEqGains);
    final gains = <int, double>{};
    if (raw != null && raw.isNotEmpty) {
      for (final part in raw.split(',')) {
        final kv = part.split('#');
        if (kv.length == 2) {
          final f = int.tryParse(kv[0]);
          final d = double.tryParse(kv[1]);
          if (f != null && d != null) gains[f] = d;
        }
      }
    }
    final preset = prefs.getString(_kEqPreset);
    return FathomSettings._(
      prefs,
      accentIndex: prefs.getInt(_kAccent) ?? 0,
      useArtAccent: prefs.getBool(_kUseArtAccent) ?? false,
      fontKey: prefs.getString(_kFont) ?? 'System',
      gapless: prefs.getBool(_kGapless) ?? true,
      speedIndex: prefs.getInt(_kSpeed) ?? 1,
      sortIndex: prefs.getInt(_kSort) ?? 0,
      eqEnabled: prefs.getBool(_kEqEnabled) ?? true,
      eqPreset: preset,
      eqGains: gains,
      shuffle: prefs.getBool(_kShuffle) ?? false,
      repeatIndex: prefs.getInt(_kRepeat) ?? 0,
    );
  }

  int get accentIndex => _accentIndex;
  bool get useArtAccent => _useArtAccent;
  Color get accent => (_useArtAccent && _extractedArtAccent != null)
      ? _extractedArtAccent!
      : kAccentSwatches[_accentIndex];
  String get fontKey => _fontKey;
  bool get gapless => _gapless;
  int get speedIndex => _speedIndex;
  int get sortIndex => _sortIndex;
  bool get eqEnabled => _eqEnabled;
  String? get eqPreset => _eqPreset;
  Map<int, double> get eqGains => Map<int, double>.of(_eqGains);
  bool get shuffle => _shuffle;
  FathomRepeatMode get repeatMode => FathomRepeatMode.values[_repeatIndex];

  void setAccentIndex(int v) {
    if (v == _accentIndex && !_useArtAccent) return;
    _accentIndex = v.clamp(0, kAccentSwatches.length - 1).toInt();
    _useArtAccent = false;
    _prefs.setInt(_kAccent, _accentIndex);
    _prefs.setBool(_kUseArtAccent, false);
    notifyListeners();
  }

  void setUseArtAccent(bool v) {
    if (v == _useArtAccent) return;
    _useArtAccent = v;
    _prefs.setBool(_kUseArtAccent, v);
    notifyListeners();
  }

  void updateArtAccent(Color? color) {
    if (_extractedArtAccent == color) return;
    _extractedArtAccent = color;
    if (_useArtAccent) {
      notifyListeners();
    }
  }

  void setFontKey(String v) {
    if (v == _fontKey) return;
    _fontKey = kFontOptions.contains(v) ? v : 'System';
    _prefs.setString(_kFont, _fontKey);
    notifyListeners();
  }

  void setGapless(bool v) {
    if (v == _gapless) return;
    _gapless = v;
    _prefs.setBool(_kGapless, v);
    notifyListeners();
  }

  void setSpeedIndex(int v) {
    if (v == _speedIndex) return;
    _speedIndex = v.clamp(0, kSpeedFactors.length - 1).toInt();
    _prefs.setInt(_kSpeed, _speedIndex);
    notifyListeners();
  }

  void setSortIndex(int v) {
    if (v == _sortIndex) return;
    _sortIndex = v;
    _prefs.setInt(_kSort, v);
    notifyListeners();
  }

  void setEqEnabled(bool v) {
    if (v == _eqEnabled) return;
    _eqEnabled = v;
    _prefs.setBool(_kEqEnabled, v);
    notifyListeners();
  }

  void stageEqGain(int centerHz, double db) => _eqGains[centerHz] = db;

  void setEqPreset(String? v) {
    if (v == _eqPreset) return;
    _eqPreset = v;
    if (v != null) {
      _prefs.setString(_kEqPreset, v);
    } else {
      _prefs.remove(_kEqPreset);
    }
    notifyListeners();
  }

  void commitEq() {
    final encoded = _eqGains.entries
        .map((e) => '${e.key}#${e.value.toStringAsFixed(2)}')
        .join(',');
    _prefs.setString(_kEqGains, encoded);
  }

  void setShuffle(bool v) {
    if (v == _shuffle) return;
    _shuffle = v;
    _prefs.setBool(_kShuffle, v);
    notifyListeners();
  }

  void setRepeatMode(FathomRepeatMode m) {
    if (m.index == _repeatIndex) return;
    _repeatIndex = m.index;
    _prefs.setInt(_kRepeat, m.index);
    notifyListeners();
  }

  void persistQueue(String? json) {
    if (json == null) {
      _prefs.remove(_kQueue);
    } else {
      _prefs.setString(_kQueue, json);
    }
  }

  Map<String, Object?>? readQueue() {
    final raw = _prefs.getString(_kQueue);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return null;
  }
}

enum FathomLibraryStatus { idle, permissionNeeded, loading, ready, failure }

class FathomLibrary extends ChangeNotifier {
  final OnAudioQuery _plugin = OnAudioQuery();

  FathomLibraryStatus _status = FathomLibraryStatus.idle;
  List<FathomTrack> _tracks = [];
  final Map<int, Future<Uint8List?>> _artCache = {};
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
  List<FathomTrack> get tracks => List.unmodifiable(_tracks);

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<Uint8List?> artFor(int id) {
    return _artCache.putIfAbsent(id, () => _fetchArtwork(id));
  }

  Uri? artUriForTrack(FathomTrack track) {
    return Uri.parse(
        'content://media/external/audio/media/${track.id}/albumart');
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

class FathomAudioHandler extends BaseAudioHandler {
  FathomAudioHandler(this._player);

  final FathomPlayer _player;

  static const Map<ProcessingState, AudioProcessingState> _stateMap = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  void sync() {
    final p = _player;
    final playing = p.audioPlayer.playing;
    final processing =
        _stateMap[p.audioPlayer.processingState] ?? AudioProcessingState.idle;
    final position = p.audioPlayer.position;
    playbackState.add(PlaybackState(
      controls: [
        if (_player.canSkipPrevious) MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        if (_player.canSkipNext) MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekBackward,
        MediaAction.seekForward
      },
      playing: playing,
      processingState: processing,
      updatePosition: position,
      bufferedPosition: p.audioPlayer.bufferedPosition,
      speed: p.audioPlayer.speed,
      queueIndex: p.selectedIndex < 0 ? null : p.selectedIndex,
    ));
  }

  void syncQueue(List<MediaItem> items, MediaItem? current) {
    queue.add(items);
    mediaItem.add(current ?? (items.isNotEmpty ? items.first : null));
  }

  @override
  Future<void> play() async => _player.playNow();

  @override
  Future<void> pause() async => _player.pauseNow();

  @override
  Future<void> stop() async => _player.stopAll();

  @override
  Future<void> skipToNext() async => _player.skipNext();

  @override
  Future<void> skipToPrevious() async => _player.skipPrevious();

  @override
  Future<void> seek(Duration position) async => _player.seekTo(position);

  @override
  Future<void> fastForward() async => _player.seekBy(10);

  @override
  Future<void> rewind() async => _player.seekBy(-10);
}

class FathomPlayer extends ChangeNotifier {
  FathomPlayer(this.settings) {
    equalizer = AndroidEqualizer();
    audioPlayer = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );

    audioPlayer.currentIndexStream.listen(_onIndexChanged);
    audioPlayer.playingStream.listen(_onPlayingChanged);
    audioPlayer.processingStateStream.listen(_onProcessingChanged);

    unawaited(initialize());
  }

  final FathomSettings settings;

  late final AndroidEqualizer equalizer;
  late final AudioPlayer audioPlayer;
  late final FathomAudioHandler handler = FathomAudioHandler(this);

  List<FathomTrack> _sourceQueue = const [];
  int _selectedIndex = -1;

  bool _eqApplied = false;
  bool _eqReady = false;
  bool _isSettingQueue = false;
  String _lastError = '';
  Future<void>? _initializeFuture;
  FathomLibrary? _libraryRef;

  void attachLibrary(FathomLibrary library) {
    _libraryRef = library;
  }

  bool get shuffle => settings.shuffle;
  FathomRepeatMode get repeatMode => settings.repeatMode;

  List<FathomTrack> get sourceQueue => List.unmodifiable(_sourceQueue);
  List<FathomTrack> get queue => List.unmodifiable(_sourceQueue);

  int get selectedIndex => _selectedIndex;
  bool get hasCurrent => queue.isNotEmpty && _selectedIndex >= 0;
  bool get eqReady => _eqReady;
  String get lastError => _lastError;
  bool get isPlaying => audioPlayer.playing;
  Duration get position => audioPlayer.position;
  Duration? get duration => audioPlayer.duration;
  double get speed => kSpeedFactors[settings.speedIndex];

  bool get canSkipNext {
    if (!hasCurrent) return false;
    if (repeatMode == FathomRepeatMode.one) return false;
    if (repeatMode == FathomRepeatMode.all) return queue.length > 1;
    return _selectedIndex < queue.length - 1;
  }

  bool get canSkipPrevious {
    if (!hasCurrent) return false;
    if (repeatMode == FathomRepeatMode.one) return false;
    if (repeatMode == FathomRepeatMode.all) return queue.length > 1;
    return _selectedIndex > 0;
  }

  FathomTrack? get currentTrack {
    if (!hasCurrent) return null;
    final q = queue;
    if (_selectedIndex < 0 || _selectedIndex >= q.length) return null;
    return q[_selectedIndex];
  }

  Future<void> initialize() => _initializeFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    try {
      await AudioService.init(
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'pharmaracist.fathom.playback',
          androidNotificationChannelName: 'Fathom Playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
        ),
        builder: () => handler,
      );
    } catch (e) {
      debugPrint('Fathom: audio_service init failed: $e');
    }

    await audioPlayer.setSpeed(speed);
  }

  Future<bool> playFrom(List<FathomTrack> list, int index) async {
    if (list.isEmpty || index < 0 || index >= list.length) return false;

    _sourceQueue = List.of(list);
    _selectedIndex = index;

    _isSettingQueue = true;
    notifyListeners();

    try {
      final sources = ConcatenatingAudioSource(
        children: _sourceQueue
            .map((t) => AudioSource.uri(Uri.parse(t.uri), tag: t.id))
            .toList(),
      );

      await audioPlayer.setAudioSource(
        sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );

      await audioPlayer.setShuffleModeEnabled(settings.shuffle);
      await audioPlayer.setLoopMode(_loopModeFor(settings.repeatMode));

      _isSettingQueue = false;
      _pushMediaItem();
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
      await audioPlayer.seek(Duration.zero, index: index);
      _pushMediaItem();
      unawaited(_startPlayback());
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> playNow() async => audioPlayer.play();
  void pauseNow() => audioPlayer.pause();

  void stopAll() {
    audioPlayer.stop();
    handler.sync();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (audioPlayer.playing) {
      pauseNow();
    } else {
      await playNow();
    }
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (canSkipNext) await audioPlayer.seekToNext();
  }

  Future<void> skipPrevious() async {
    if (audioPlayer.position > const Duration(seconds: 3)) {
      await audioPlayer.seek(Duration.zero);
      return;
    }
    if (canSkipPrevious) await audioPlayer.seekToPrevious();
  }

  Future<void> seekTo(Duration position) async {
    await audioPlayer.seek(position);
    handler.sync();
    notifyListeners();
  }

  Future<void> seekBy(int seconds) async {
    final d = Duration(seconds: seconds);
    final p = audioPlayer.position;
    final target = p + d;
    final max = duration ?? const Duration(hours: 1);
    final clamped =
        target < Duration.zero ? Duration.zero : (target > max ? max : target);
    await audioPlayer.seek(clamped);
    handler.sync();
  }

  Future<void> setSpeedFactor(double factor) async {
    await audioPlayer.setSpeed(factor);
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    final next = !settings.shuffle;
    settings.setShuffle(next);
    await audioPlayer.setShuffleModeEnabled(next);
    handler.sync();
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    final next = FathomRepeatMode.values[
        (settings.repeatMode.index + 1) % FathomRepeatMode.values.length];
    settings.setRepeatMode(next);
    await audioPlayer.setLoopMode(_loopModeFor(next));
    handler.sync();
    notifyListeners();
  }

  LoopMode _loopModeFor(FathomRepeatMode mode) {
    switch (mode) {
      case FathomRepeatMode.off:
        return LoopMode.off;
      case FathomRepeatMode.all:
        return LoopMode.all;
      case FathomRepeatMode.one:
        return LoopMode.one;
    }
  }

  void removeAt(int index) {
    if (index < 0 || index >= _sourceQueue.length) return;
    _sourceQueue = List.of(_sourceQueue)..removeAt(index);

    if (_sourceQueue.isEmpty) {
      _selectedIndex = -1;
      audioPlayer.stop();
    } else if (index < _selectedIndex) {
      _selectedIndex -= 1;
    }

    _pushMediaItem();
    handler.sync();
    notifyListeners();
  }

  void moveAt(int from, int to) {
    if (from < 0 || from >= _sourceQueue.length) return;
    if (to < 0 || to > _sourceQueue.length) return;
    if (from == to) return;

    _sourceQueue = List.of(_sourceQueue);
    final track = _sourceQueue.removeAt(from);
    final insertIndex = from < to ? to - 1 : to;
    _sourceQueue.insert(insertIndex, track);

    if (_selectedIndex == from) {
      _selectedIndex = insertIndex;
    } else if (from < _selectedIndex && _selectedIndex <= insertIndex) {
      _selectedIndex -= 1;
    } else if (insertIndex <= _selectedIndex && _selectedIndex < from) {
      _selectedIndex += 1;
    }

    _pushMediaItem();
    handler.sync();
    notifyListeners();
  }

  Future<void> _startPlayback() async {
    try {
      unawaited(_tryApplyEqualizer());
      if (hasCurrent) unawaited(_extractArtAccent(currentTrack!.id));
      await audioPlayer.play();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _onIndexChanged(int? idx) {
    if (_isSettingQueue || idx == null) return;
    if (idx != _selectedIndex) {
      _selectedIndex = idx;
      _pushMediaItem();
      handler.sync();
      if (hasCurrent) {
        unawaited(_extractArtAccent(currentTrack!.id));
      }
      notifyListeners();
    }
  }

  void _onPlayingChanged(bool playing) {
    handler.sync();
    notifyListeners();
  }

  void _onProcessingChanged(ProcessingState ps) {
    handler.sync();
  }

  Future<void> _extractArtAccent(int trackId) async {
    if (_libraryRef == null || !settings.useArtAccent) return;

    try {
      final bytes = await _libraryRef!.artFor(trackId);
      if (bytes == null || bytes.isEmpty) {
        settings.updateArtAccent(null);
        return;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 16,
      );

      final color = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color;

      settings.updateArtAccent(color);
    } catch (_) {
      settings.updateArtAccent(null);
    }
  }

  void setBandGain(int centerHz, double db, {bool persist = false}) {
    unawaited(_setBandOnDevice(centerHz, db));
    if (settings.eqPreset != null) settings.setEqPreset(null);
    settings.stageEqGain(centerHz, db);
    if (persist) settings.commitEq();
  }

  Future<void> _setBandOnDevice(int centerHz, double db) async {
    if (!_eqReady) return;
    try {
      final params = await equalizer.parameters;
      for (final band in params.bands) {
        if (band.centerFrequency.toInt() == centerHz) {
          final clamped =
              db.clamp(params.minDecibels, params.maxDecibels).toDouble();
          await band.setGain(clamped);
        }
      }
    } catch (_) {}
  }

  Future<void> applyEqPreset(String preset) async {
    if (!kEqPresetGains10.containsKey(preset)) return;
    settings.setEqPreset(preset);
    settings._eqGains.clear();
    if (!_eqReady) return;

    try {
      final params = await equalizer.parameters;
      final gains10 = kEqPresetGains10[preset]!;

      for (var i = 0; i < params.bands.length; i++) {
        final band = params.bands[i];
        final hz = band.centerFrequency.toInt();

        final idx = kEq10Bands.indexOf(hz);
        final db = idx != -1 ? gains10[idx] : 0.0;
        final clamped = db.clamp(params.minDecibels, params.maxDecibels).toDouble();

        await band.setGain(clamped);
        settings.stageEqGain(hz, clamped);
      }
      settings.commitEq();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setDeviceEqualizerEnabled(bool enabled) async {
    settings.setEqEnabled(enabled);
    if (!_eqReady) return;
    try {
      await equalizer.setEnabled(enabled);
    } catch (_) {}
  }

  Future<void> _tryApplyEqualizer() async {
    if (_eqApplied) return;
    _eqApplied = true;
    try {
      final params = await equalizer.parameters;
      _eqReady = true;

      final gains = settings.eqGains;
      final preset = settings.eqPreset;
      final presetGains = preset != null ? kEqPresetGains10[preset] : null;

      for (var i = 0; i < params.bands.length; i++) {
        final band = params.bands[i];
        final hz = band.centerFrequency.toInt();
        double? db;

        if (gains.containsKey(hz)) {
          db = gains[hz];
        } else if (presetGains != null) {
          final idx = kEq10Bands.indexOf(hz);
          if (idx != -1) db = presetGains[idx];
        }

        if (db != null) {
          final clamped =
              db.clamp(params.minDecibels, params.maxDecibels).toDouble();
          await band.setGain(clamped);
        }
      }
      await equalizer.setEnabled(settings.eqEnabled);
    } catch (_) {
      _eqReady = false;
      _eqApplied = false;
    }
    notifyListeners();
  }

  MediaItem _mediaItemFor(FathomTrack t) {
    final dur =
        t.durationMs == null ? null : Duration(milliseconds: t.durationMs!);
    final artUri = _libraryRef?.artUriForTrack(t);

    return MediaItem(
      id: t.uri,
      title: t.title,
      artist: t.artist,
      duration: dur,
      artUri: artUri,
    );
  }

  void _pushMediaItem() {
    if (hasCurrent) {
      handler.mediaItem.add(_mediaItemFor(currentTrack!));
    }
  }

  Future<void> ensureEqReady() async {
    await _tryApplyEqualizer();
  }
}
