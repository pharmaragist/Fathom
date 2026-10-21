import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
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

  /// How long the source may take to hand back a media address.
  ///
  /// Resolving is one network round trip to YouTube, so a small multiple of a
  /// normal request is generous without letting a dead connection hold a
  /// concurrency slot.
  static const Duration resolveTimeout = Duration(seconds: 30);

  /// How long the audio download may take, end to end.
  ///
  /// This bound exists for the same reason the resolve one does, and covers more
  /// ground: `_fetch` sets `connectionTimeout`, but that only governs the TCP
  /// connect, so a server that accepts the connection and then stalls mid-body
  /// hangs forever, as does the per-chunk `await for`. A stalled transfer is
  /// indistinguishable from a slow one until it is bounded, so the whole
  /// transfer is bounded rather than each chunk.
  static const Duration transferTimeout = Duration(minutes: 10);

  /// How long the mp4 remux and tag may take.
  ///
  /// A stream copy of a few megabytes is work measured in milliseconds, so this
  /// only ever fires on a malformed input that leaves FFmpeg reading forever.
  static const Duration remuxTimeout = Duration(minutes: 2);

  final Map<String, int> _manifest = {};
  final Map<String, DownloadState> _states = {};
  final Map<String, double> _progress = {};
  final Map<String, String> _failures = {};
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

  /// Why the last attempt at this item failed, or null if it has not failed.
  ///
  /// The reason is deliberately not folded into the download's bool result: a
  /// caller that only needs "did it work" should not have to carry a message,
  /// and a caller that shows one reads it here. It is cleared when the item is
  /// retried, so it can never be shown for an attempt still in flight.
  String? failureOf(String? videoId) =>
      videoId == null ? null : _failures[videoId];

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
    _failures.remove(videoId);
    notifyListeners();

    File? tempAudio;
    File? tempArt;
    File? taggedAudio;
    var ok = false;
    try {
      // Resolving an address is a network round trip to YouTube that can stall
      // without ever closing its socket, and `connectionTimeout` on the fetch
      // below does not cover it. Without a bound here a stuck resolve holds one
      // of the three concurrency slots forever and the row spins indefinitely,
      // so the message the user is waiting on never arrives.
      //
      // `resolve` returns the item's own best cover art from the same call: the
      // extractor fetches the video's metadata anyway, so the image is free
      // here and far better than the row-sized URL the search kept.
      ResolvedAudio? resolved;
      try {
        resolved = await source.resolve(videoId).timeout(resolveTimeout);
      } on TimeoutException {
        _failures[videoId] = 'YouTube did not answer in time';
      }
      if (resolved == null) {
        // The source answers null instead of throwing, so its own explanation
        // is the only account of what went wrong; without it the user sees
        // "could not save" and has nothing to act on. The timeout above has
        // already written the reason when the failure was a timeout.
        _fail(
          videoId,
          _failures[videoId] ??
              source.lastResolveError ??
              'No audio address for this track',
        );
      } else {
        // The artwork is an independent request against a different host, so it
        // is started alongside the audio rather than after it. Awaiting it in
        // sequence made every download pay audio **plus** artwork; together the
        // download costs whichever is slower, and on a slow connection that is
        // a whole round trip saved per track.
        final artwork = _downloadArtwork(
          resolved.artwork?.toString() ?? track.artworkUrl,
          videoId,
        );

        // `_fetch` sets `connectionTimeout`, but that only governs the TCP
        // connect, so a server that accepts the connection and then stalls
        // mid-body hangs forever. A stalled transfer is indistinguishable from
        // a slow one until it is bounded.
        try {
          tempAudio = await _fetch(resolved.audio, videoId).timeout(
            transferTimeout,
            onTimeout: () => throw const SocketException(
              'Audio transfer stalled and was given up on',
            ),
          );
        } finally {
          // Whatever happened to the audio, the artwork future has to be
          // awaited or its failure would surface as an unhandled error.
          tempArt = await artwork;
        }

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
    return _awaitRemux(session, outputFile, audioFile);
  }

  /// Waits for a remux, bounded by [remuxTimeout].
  ///
  /// The remux is a stream copy, so it is fast, but this is the one step in the
  /// chain with no socket underneath it to time out: a malformed input can leave
  /// FFmpeg reading forever, and its session would hold a concurrency slot for
  /// the rest of the run. On timeout the session is cancelled rather than
  /// abandoned, so the native process goes away too, and the audio already on
  /// disk is returned instead — the tag is a nicety, not the download, so losing
  /// it must not lose the file.
  Future<File> _awaitRemux(
    FFmpegSession session,
    File outputFile,
    File audioFile,
  ) async {
    final returnCode =
        await session.getReturnCode().timeout(remuxTimeout, onTimeout: () {
      unawaited(FFmpegKit.cancel(session.getSessionId()));
      return null;
    });

    if (returnCode != null &&
        ReturnCode.isSuccess(returnCode) &&
        outputFile.existsSync()) {
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
    _failures[videoId] = reason;
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
