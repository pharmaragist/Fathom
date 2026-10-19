import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

import '../models/tracks.dart';
import '../services/audio.dart';
import '../services/equalizer.dart';
import 'constants.dart';
import 'library.dart';
import 'settings.dart';

class FathomPlayer extends ChangeNotifier {
  FathomPlayer(this.settings) {
    _hardwareEqualizer = AndroidEqualizer();
    _audioPlayer = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_hardwareEqualizer]),
    );

    _subscriptions.addAll([
      _audioPlayer.currentIndexStream.listen(_onIndexChanged),
      _audioPlayer.playingStream.listen((_) => _onPlayerStateUpdate()),
      _audioPlayer.processingStateStream.listen((_) => _onPlayerStateUpdate()),
      _audioPlayer.androidAudioSessionIdStream.listen((_) => ensureEqReady()),
    ]);
  }

  final FathomSettings settings;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

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
  bool _isSettingQueue = false;
  String _lastError = '';
  Future<void>? _initializeFuture;
  FathomLibrary? _libraryRef;

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
  AndroidEqualizer get equalizer => _hardwareEqualizer;
  AndroidEqualizer get hardwareEqualizer => _hardwareEqualizer;

  bool get canSkipNext {
    if (!hasCurrent) return false;
    switch (repeatMode) {
      case FathomRepeatMode.one:
        return false;
      case FathomRepeatMode.all:
        return queue.length > 1;
      case FathomRepeatMode.off:
        return _selectedIndex < queue.length - 1;
    }
  }

  bool get canSkipPrevious {
    if (!hasCurrent) return false;
    switch (repeatMode) {
      case FathomRepeatMode.one:
        return false;
      case FathomRepeatMode.all:
        return queue.length > 1;
      case FathomRepeatMode.off:
        return _selectedIndex > 0;
    }
  }

  void attachLibrary(FathomLibrary library) => _libraryRef = library;

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
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<bool> playFrom(List<FathomTrack> list, int index) async {
    if (list.isEmpty || index < 0 || index >= list.length) return false;

    _sourceQueue = List.of(list);
    _selectedIndex = index;
    _isSettingQueue = true;
    notifyListeners();

    try {
      final sources = _sourceQueue
          .map((t) => AudioSource.uri(Uri.parse(t.uri), tag: t.id))
          .toList();

      await _audioPlayer.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );

      await _audioPlayer.setShuffleModeEnabled(shuffle);
      await _audioPlayer.setLoopMode(_loopModeFor(repeatMode));

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
      await _audioPlayer.seek(Duration.zero, index: index);
      _pushMediaItem();
      unawaited(_startPlayback());
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void removeAt(int index) {
    if (index < 0 || index >= _sourceQueue.length) return;
    _sourceQueue = List.of(_sourceQueue)..removeAt(index);

    if (_sourceQueue.isEmpty) {
      _selectedIndex = -1;
      _audioPlayer.stop();
    } else if (index < _selectedIndex) {
      _selectedIndex -= 1;
    }

    _pushMediaItem();
    _handler?.sync();
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
    _handler?.sync();
    notifyListeners();
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
  }

  Future<void> seekBy(int seconds) async {
    final target = _audioPlayer.position + Duration(seconds: seconds);
    final max = duration ?? const Duration(hours: 1);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target);
    await _audioPlayer.seek(clamped);
    _handler?.sync();
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

  Future<void> ensureEqReady() => _tryApplyEqualizer();

  void setBandGain(int centerHz, double db, {bool persist = false}) {
    unawaited(_setBandGain(centerHz, db));
    if (settings.get<String?>(SettingKey.eqPreset) != null) {
      settings.set<String?>(SettingKey.eqPreset, null);
    }
    settings.stageEqGain(centerHz, db);
    if (persist) settings.commitEq();
  }

  /// Sets the preamp (input gain) used by the native equalizer, in decibels.
  ///
  /// The hardware fallback has no preamp stage, so this is a no-op there.
  void setPreamp(double db, {bool persist = false}) {
    final clamped =
        db.clamp(-FathomNativeEqualizer.maxPreampDecibels, FathomNativeEqualizer.maxPreampDecibels);
    if (_nativeEqReady) unawaited(_nativeEq.setPreamp(clamped));
    settings.stageEqPreamp(clamped);
    if (persist) settings.commitEq();
  }

  Future<void> _setBandGain(int centerHz, double db) async {
    if (_nativeEqReady) {
      final idx = kEq10Bands.indexOf(centerHz);
      if (idx >= 0) {
        final clamped = db.clamp(
          FathomNativeEqualizer.minDecibels,
          FathomNativeEqualizer.maxDecibels,
        );
        await _nativeEq.setGain(idx, clamped);
        return;
      }
    }
    await _setBandOnDevice(centerHz, db);
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
        await _nativeEq.setGains(target);
        if (preamp != null) await _nativeEq.setPreamp(preamp);
        for (var i = 0; i < kEq10Bands.length; i++) {
          settings.stageEqGain(kEq10Bands[i], target[i]);
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
    notifyListeners();
  }

  /// The live ten band gains in [kEq10Bands] order, favouring explicit band
  /// overrides and falling back to the selected preset.
  List<double> _bandGains10() {
    final gains = settings.eqGains;
    final presetGains = _presetGains(settings.get<String?>(SettingKey.eqPreset));
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
      await _nativeEq.setEnabled(enabled);
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

  Future<void> _tryApplyEqualizer() async {
    if (_eqApplied) return;

    if (!await _nativeEq.isSupported()) {
      await _applyHardwareEqualizer();
      return;
    }

    final sessionId = _audioPlayer.androidAudioSessionId;
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
      );
      if (attached) {
        _nativeEqReady = true;
        _eqApplied = true;
        await _applyNativeEqualizer();
        _eqReady = true;
        notifyListeners();
        return;
      }
    } catch (_) {
      _nativeEq.detach();
    }

    await _applyHardwareEqualizer();
  }

  Future<void> _applyHardwareEqualizer() async {
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
      await _hardwareEqualizer.setEnabled(settings.get<bool>(SettingKey.eqEnabled));
      _eqApplied = true;
    } catch (_) {
      _eqReady = false;
      _eqApplied = false;
    }
    notifyListeners();
  }

  Future<void> _applyNativeEqualizer() async {
    if (!_nativeEqReady) return;
    try {
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

      await _nativeEq.setGains(target);
      await _nativeEq.setPreamp(settings.eqPreamp);
      await _nativeEq.setEnabled(settings.get<bool>(SettingKey.eqEnabled));
    } catch (_) {}
  }

  Future<void> _startPlayback() async {
    try {
      unawaited(_tryApplyEqualizer());
      if (hasCurrent) unawaited(_extractArtAccent(currentTrack!.id));
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
    if (hasCurrent) unawaited(_extractArtAccent(currentTrack!.id));
    notifyListeners();
  }

  void _onPlayerStateUpdate() {
    _handler?.sync();
    notifyListeners();
  }

  Future<void> _extractArtAccent(int trackId) async {
    final library = _libraryRef;
    if (library == null || !settings.get<bool>(SettingKey.useArtAccent)) return;

    try {
      final bytes = await library.artFor(trackId);
      if (bytes == null || bytes.isEmpty) {
        settings.updateArtAccent(null);
        return;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 16,
      );

      settings.updateArtAccent(
        palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            palette.dominantColor?.color,
      );
    } catch (_) {
      settings.updateArtAccent(null);
    }
  }

  MediaItem _mediaItemFor(FathomTrack t) {
    final artUri = _libraryRef?.artUriForTrack(t);
    return MediaItem(
      id: t.uri,
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
