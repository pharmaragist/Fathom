import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracks.dart';
import 'yt_source.dart';

enum DownloadState { idle, pending, running, done, failed }

class FathomDownloads extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('pharmaracist.fathom/downloads');

  static const _manifestKey = 'downloads.manifest.v1';

  FathomDownloads({required this.source, required this.onFinished}) {
    _loadManifest();
  }

  final FathomYtSource source;
  final VoidCallback onFinished;

  static const int maxConcurrent = 3;

  final Map<String, int> _manifest = {};
  final Map<String, DownloadState> _states = {};
  final Map<String, double> _progress = {};
  final Map<String, Completer<bool>> _waiters = {};
  final List<FathomTrack> _queue = [];
  int _active = 0;

  final Completer<void> _manifestReady = Completer<void>();

  Future<void> _loadManifest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_manifestKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is int) {
              _manifest[entry.key as String] = entry.value as int;
            }
          }
        }
      }
    } catch (_) {}
    _manifestReady.complete();
    notifyListeners();
  }

  Future<void> _persistManifest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_manifestKey, jsonEncode(_manifest));
    } catch (_) {}
  }

  bool isDone(String? videoId) =>
      videoId != null && _manifest.containsKey(videoId);

  bool isDownloadedDeviceTrack(int mediaId) =>
      mediaId >= 0 && _manifest.containsValue(mediaId);

  DownloadState stateOf(String? videoId) => videoId == null
      ? DownloadState.idle
      : (_states[videoId] ?? DownloadState.idle);

  double progressOf(String? videoId) =>
      videoId == null ? 1.0 : (_progress[videoId] ?? 1.0);

  Future<bool> download(FathomTrack track) async {
    await _manifestReady.future;

    final videoId = track.videoId;
    if (videoId == null) return false;
    if (_manifest.containsKey(videoId)) return false;

    final waiting = _waiters[videoId];
    if (waiting != null) return waiting.future;

    final completer = Completer<bool>();
    _waiters[videoId] = completer;

    if (_active >= maxConcurrent) {
      _states[videoId] = DownloadState.pending;
      _progress[videoId] = 0.0;
      _queue.add(track);
      notifyListeners();
    } else {
      unawaited(_run(track));
    }
    return completer.future;
  }

  Future<void> _run(FathomTrack track) async {
    final videoId = track.videoId!;
    _active++;
    _states[videoId] = DownloadState.running;
    _progress[videoId] = 0.0;
    notifyListeners();

    File? tempAudio;
    File? tempArt;
    File? taggedAudio;
    var ok = false;
    try {
      final address = await source.audioUri(videoId);
      if (address == null) {
        _fail(videoId, 'No audio address for this track');
      } else {
        tempAudio = await _fetch(address, videoId);
        tempArt = await _downloadArtwork(track.artworkUrl, videoId);

        taggedAudio = await _remuxAndTag(
          audioFile: tempAudio,
          artFile: tempArt,
          title: track.title,
          artist: track.artist,
          videoId: videoId,
        );

        final row =
            await _channel.invokeMethod<int>('saveAudio', <String, Object?>{
          'path': taggedAudio.path,
          'title': track.title,
          'artist': track.artist,
          'artworkPath': tempArt?.path,
        });

        _manifest[videoId] = row ?? -1;
        _states[videoId] = DownloadState.done;
        _progress[videoId] = 1.0;
        await _persistManifest();
        ok = true;
      }
    } catch (e) {
      _fail(videoId, e.toString());
    } finally {
      tempAudio?.delete().ignore();
      tempArt?.delete().ignore();
      taggedAudio?.delete().ignore();
      _active--;
      final waiter = _waiters.remove(videoId);
      waiter?.complete(ok);
      _drain();
      notifyListeners();
      if (ok) onFinished();
    }
  }

  Future<File> _remuxAndTag({
    required File audioFile,
    required File? artFile,
    required String title,
    required String artist,
    required String videoId,
  }) async {
    final outputPath =
        '${Directory.systemTemp.path}/fathom-tagged-$videoId.m4a';
    final outputFile = File(outputPath);

    final cleanTitle = title.replaceAll('"', '\\"');
    final cleanArtist = artist.replaceAll('"', '\\"');

    final cmd = StringBuffer();
    cmd.write('-y -i "${audioFile.path}" ');
    if (artFile != null && artFile.existsSync()) {
      cmd.write(
          '-i "${artFile.path}" -map 0:a -map 1:v -c copy -disposition:v:0 attached_pic ');
    } else {
      cmd.write('-map 0:a -c copy ');
    }
    cmd.write('-metadata title="$cleanTitle" ');
    cmd.write('-metadata artist="$cleanArtist" ');
    cmd.write('-metadata album="Fathom" ');
    cmd.write('"$outputPath"');

    final session = await FFmpegKit.execute(cmd.toString());
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) && outputFile.existsSync()) {
      return outputFile;
    }
    return audioFile;
  }

  Future<File?> _downloadArtwork(String? url, String videoId) async {
    if (url == null || url.isEmpty) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == HttpStatus.ok) {
        final bytes = await consolidateHttpClientResponseBytes(res);
        final file = File('${Directory.systemTemp.path}/art-$videoId.jpg');
        await file.writeAsBytes(bytes);
        client.close(force: true);
        return file;
      }
      client.close(force: true);
    } catch (_) {}
    return null;
  }

  void _drain() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      unawaited(_run(_queue.removeAt(0)));
    }
  }

  void _fail(String videoId, String reason) {
    debugPrint('Fathom download $videoId: $reason');
    _states[videoId] = DownloadState.failed;
    _progress[videoId] = 0.0;
    notifyListeners();
  }

  Future<File> _fetch(Uri address, String videoId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final part = File('${Directory.systemTemp.path}/fathom-dl-$videoId.part');
    try {
      final request = await client.getUrl(address);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Audio server said ${response.statusCode}');
      }

      final total = response.contentLength;
      final out = part.openWrite();
      var received = 0;
      var lastNotified = 0.0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          out.add(chunk);
          if (total > 0) {
            final fraction = (received / total).clamp(0.0, 1.0);
            if (fraction - lastNotified >= 0.01) {
              lastNotified = fraction;
              _progress[videoId] = fraction;
              notifyListeners();
            }
          }
        }
        await out.flush();
      } finally {
        await out.close();
      }

      final ext = await _sniffExtension(part);
      return await part.rename(
        '${part.parent.path}/fathom-dl-$videoId.$ext',
      );
    } catch (_) {
      part.delete().ignore();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _sniffExtension(File file) async {
    try {
      final raf = await file.open();
      final head = await raf.read(12);
      await raf.close();
      if (head.length >= 8 &&
          head[4] == 0x66 &&
          head[5] == 0x74 &&
          head[6] == 0x79 &&
          head[7] == 0x70) {
        return 'm4a';
      }
      if (head.length >= 4 &&
          head[0] == 0x1A &&
          head[1] == 0x45 &&
          head[2] == 0xDF &&
          head[3] == 0xA3) {
        return 'webm';
      }
    } catch (_) {}
    return 'm4a';
  }
}
