import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../common/player.dart';

class FathomAudioSession {
  FathomAudioSession._();

  static Future<void> configure() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('Fathom: Audio session configuration failed: $e');
    }
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

    playbackState.add(
      PlaybackState(
        controls: [
          if (_player.canSkipPrevious) MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          if (_player.canSkipNext) MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekBackward,
          MediaAction.seekForward,
        },
        playing: playing,
        processingState: processing,
        updatePosition: position,
        bufferedPosition: p.audioPlayer.bufferedPosition,
        speed: p.audioPlayer.speed,
        queueIndex: p.selectedIndex < 0 ? null : p.selectedIndex,
      ),
    );
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
