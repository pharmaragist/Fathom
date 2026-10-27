import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracks.dart';
import '../models/ytmusic.dart';
import 'artwork.dart';
import 'yt_source.dart';

enum DownloadState { idle, pending, running, done, failed }

/// The size of one ranged request.
const int kDownloadChunkBytes = 1024 * 1024;

/// A transfer larger than this is split into ranges.
///
/// YouTube throttles a single long-lived download, so a whole file fetched as
/// one response crawls at a fraction of the link's speed. Ranged requests are
/// served from separate connections and do not sit in that throttle, which is
/// why the same audio arrives an order of magnitude faster.
const int kDownloadChunkThresholdBytes = 1024 * 1024;

/// How many ranges may be in flight at once.
///
/// Three is enough to leave the throttle behind without opening so many
/// connections that a phone's link is saturated by per-connection overhead.
const int kDownloadChunkConcurrency = 3;

/// One inclusive byte range of a download.
@immutable
class DownloadRange {
  const DownloadRange(this.start, this.end);

  /// First byte in the range, zero based.
  final int start;

  /// Last byte in the range, inclusive.
  final int end;

  int get length => end - start + 1;

  @override
  String toString() => 'DownloadRange($start-$end)';
}

/// Raised when a ranged request was answered with the whole file instead.
///
/// It is a distinct type because it must not be retried: the server has shown
/// it does not honour Range, so every further chunk would download the file
/// again. The transfer abandons chunking on this, where any other failure gets
/// one retry.
class _RangeUnsupported implements Exception {
  const _RangeUnsupported();
}

/// Splits [totalBytes] into contiguous ranges of at most [chunkSize].
///
/// Pure and total: an empty or negative total yields no ranges, and a total
/// that divides exactly yields no zero-length tail range. The download uses the
/// result to address `Range` requests, so an off-by-one here would either drop
/// the last byte of every file or ask for one byte past its end.
List<DownloadRange> planDownloadRanges(
  int totalBytes, {
  int chunkSize = kDownloadChunkBytes,
}) {
  if (totalBytes <= 0 || chunkSize <= 0) return const [];
  final ranges = <DownloadRange>[];
  var start = 0;
  while (start < totalBytes) {
    final end = start + chunkSize - 1;
    ranges.add(DownloadRange(start, end < totalBytes ? end : totalBytes - 1));
    start = end + 1;
  }
  return ranges;
}

/// One download the service still has an opinion about.
///
/// A finished download is *not* one of these: the file is on the device by
/// then, and the library owns it (see `FathomDownloads.downloadedMediaIds`).
/// This is the work that has no file yet — queued, running, or failed.
@immutable
class DownloadEntry {
  const DownloadEntry({
    required this.videoId,
    required this.track,
    required this.state,
    this.failure,
  });

  /// The remote item's id, which is how every other part of Fathom names it.
  final String videoId;

  /// The item that was asked for, kept whole so a failed attempt can be
  /// retried without the caller having to find the item again.
  final FathomTrack track;

  final DownloadState state;

  /// Why the attempt failed, or null while it is still running.
  final String? failure;
}

class FathomDownloads extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('pharmaracist.fathom/downloads');

  static const _manifestKey = 'downloads.manifest.v1';

  FathomDownloads({required this.source, required this.onFinished}) {
    _loadManifest();
  }

  /// Asks Android for the playback notification permission.
  ///
  /// Requested from the first-run walkthrough rather than at construction, so
  /// the dialog appears with an explanation instead of over a launching app.
  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
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

  final Map<String, int> _manifest = {};
  final Map<String, DownloadState> _states = {};
  final Map<String, double> _progress = {};
  final Map<String, String> _failures = {};
  final Map<String, Completer<bool>> _waiters = {};
  final List<FathomTrack> _queue = [];
  final Map<String, String> _titles = {};
  int _active = 0;

  /// The remote items this session asked for and has not finished with.
  ///
  /// Held so a surface can list what is outstanding and retry what failed: the
  /// item itself is the only thing a retry needs, and it is gone from every
  /// other list once the download starts.
  final Map<String, FathomTrack> _tracked = {};

  /// The media ids of the files Fathom has fetched, oldest first.
  ///
  /// The manifest is the durable record; this is that record read the way a
  /// list needs it. It is replaced rather than mutated, so a surface that
  /// selects on it rebuilds when the set changes and not otherwise.
  List<int> _mediaIds = const [];

  /// The cached view of [_tracked] for a surface that lists downloads.
  ///
  /// Rebuilt when a download changes *state*, never on a progress tick: a
  /// running download reports progress constantly, and a list that rebuilt on
  /// every one of those reports would spend its time rebuilding.
  List<DownloadEntry> _entries = const [];

  String? _currentTrackTitleFor(String videoId) => _titles[videoId];

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
      // The manifest says which files are ours; the id list is the same record
      // read the way a list needs it. A row id of -1 means the file landed but
      // the store did not name it, and it cannot be pointed at either.
      _mediaIds = List.unmodifiable(
        _manifest.values.where((id) => id >= 0),
      );
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

  /// The remote item a fetched file came from, or null when the id is not ours.
  ///
  /// This is the reverse of the manifest's one mapping, and it is what lets a
  /// device track recovered by a later library scan find the artwork the
  /// download already cached. A row id of `-1` means the file landed without a
  /// store id; it is not ours to name and never matches.
  String? videoIdForMediaId(int mediaId) {
    if (mediaId < 0) return null;
    for (final entry in _manifest.entries) {
      if (entry.value == mediaId) return entry.key;
    }
    return null;
  }

  /// Completes once the persisted manifest has been read.
  ///
  /// [download] already waits for it internally. The artwork fallback awaits it
  /// too, because a cold start can ask which file a media id came from before
  /// the disk read has finished.
  Future<void> get manifestReady => _manifestReady.future;

  /// The downloads this session still owes the user: the ones queued or
  /// running, and the ones that failed.
  ///
  /// A finished download is not here — the file is on the device by then, and
  /// the library owns it, so [downloadedMediaIds] is the other half of what a
  /// downloads list shows.
  ///
  /// The list is cached and rebuilt only when a download changes state, so a
  /// surface can select on it without rebuilding several times a second.
  /// Progress is not part of it; that is read per row.
  List<DownloadEntry> get entries => _entries;

  /// The media ids of the files Fathom has fetched, oldest first.
  ///
  /// The manifest is the durable record of a download; this is the same record
  /// read the way a list needs it: which files on the device are ours.
  List<int> get downloadedMediaIds => _mediaIds;

  /// Drops a failed download from the list.
  ///
  /// Nothing on the device changes — the file was never written — so this only
  /// clears the record of the attempt, and a row the user has dismissed does
  /// not come back on the next rebuild.
  void forget(String videoId) {
    final known = _tracked.remove(videoId) != null ||
        _states.containsKey(videoId) ||
        _failures.containsKey(videoId);
    if (!known) return;
    _states.remove(videoId);
    _progress.remove(videoId);
    _failures.remove(videoId);
    _syncEntries();
    notifyListeners();
  }

  /// Drops finished downloads whose files were deleted from the device.
  ///
  /// A deleted file is not a download any more. The manifest is what makes a
  /// remote result show as "already fetched", so leaving its entry behind would
  /// make that result permanently un-downloadable even though nothing is left
  /// on disk. The media-id list is replaced rather than mutated, exactly like
  /// the add path, so selecting surfaces rebuild.
  void forgetMediaIds(Set<int> mediaIds) {
    if (mediaIds.isEmpty) return;

    final removed = <String>[];
    for (final entry in _manifest.entries) {
      if (mediaIds.contains(entry.value)) removed.add(entry.key);
    }
    if (removed.isEmpty) return;

    for (final videoId in removed) {
      _manifest.remove(videoId);
      _states.remove(videoId);
      _progress.remove(videoId);
      _tracked.remove(videoId);
    }
    _mediaIds = List.unmodifiable(
      _manifest.values.where((id) => id >= 0),
    );
    unawaited(_persistManifest());
    _syncEntries();
    notifyListeners();
  }

  /// Rebuilds the cached list of tracked downloads.
  void _syncEntries() {
    _entries = [
      for (final entry in _tracked.entries)
        DownloadEntry(
          videoId: entry.key,
          track: entry.value,
          state: _states[entry.key] ?? DownloadState.idle,
          failure: _failures[entry.key],
        ),
    ];
  }

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
    _tracked[videoId] = track;

    if (_active >= maxConcurrent) {
      _states[videoId] = DownloadState.pending;
      _progress[videoId] = 0.0;
      _queue.add(track);
      _syncEntries();
      notifyListeners();
    } else {
      unawaited(_run(track));
    }
    return completer.future;
  }

  Future<void> startDownloadNotification({
    required String videoId,
    required String title,
  }) async {
    try {
      await _channel.invokeMethod('startDownloadNotification', {
        'videoId': videoId,
        'title': title,
      });
    } catch (_) {}
  }

  Future<void> updateDownloadProgress({
    required String videoId,
    required String title,
    required int progress,
  }) async {
    try {
      await _channel.invokeMethod('updateDownloadProgress', {
        'videoId': videoId,
        'title': title,
        'progress': progress,
      });
    } catch (_) {}
  }

  Future<void> completeDownloadNotification({
    required String videoId,
    required String title,
  }) async {
    try {
      await _channel.invokeMethod('completeDownloadNotification', {
        'videoId': videoId,
        'title': title,
      });
    } catch (_) {}
  }

  Future<void> cancelDownloadNotification({required String videoId}) async {
    try {
      await _channel.invokeMethod('cancelDownloadNotification', {
        'videoId': videoId,
      });
    } catch (_) {}
  }

  Future<void> _run(FathomTrack track) async {
    final videoId = track.videoId!;
    _titles[videoId] = track.title;
    _active++;
    _states[videoId] = DownloadState.running;
    _progress[videoId] = 0.0;
    // A retry clears the old reason here, so the row cannot show the cause of
    // an attempt that is no longer the one in flight.
    _failures.remove(videoId);
    _syncEntries();
    notifyListeners();
    unawaited(startDownloadNotification(videoId: videoId, title: track.title));

    File? tempAudio;
    File? tempArt;
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
          _artworkCandidates(resolved, track),
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

        final row =
            await _channel.invokeMethod<int>('saveAudio', <String, Object?>{
          'path': tempAudio.path,
          'title': track.title,
          'artist': track.artist,
          // MediaStore treats the audio columns as metadata of the file, not
          // as values an insert owns: a row whose file carries no tags is
          // rescanned from the filename. The native side embeds this in the
          // m4a and writes the same values into the row, so the next library
          // scan reads real title/artist/album instead of the file name.
          'album': 'Fathom',
          'durationMs': track.durationMs,
          'artworkPath': tempArt?.path,
        });

        _manifest[videoId] = row ?? -1;
        _states[videoId] = DownloadState.done;
        _progress[videoId] = 1.0;
        if (row != null && row >= 0) {
          _mediaIds = List.unmodifiable([..._mediaIds, row]);
        }
        await _persistManifest();
        ok = true;
        unawaited(
            completeDownloadNotification(videoId: videoId, title: track.title));
      }
    } catch (e) {
      _fail(videoId, e.toString());
    } finally {
      tempAudio?.delete().ignore();
      tempArt?.delete().ignore();
      _titles.remove(videoId);
      _active--;
      final waiter = _waiters.remove(videoId);
      waiter?.complete(ok);
      _drain();
      if (ok) {
        // The file is on the device now, so the library owns it and this
        // service has nothing left to track about it.
        _tracked.remove(videoId);
      }
      _syncEntries();
      notifyListeners();
      if (ok) onFinished();
    }
  }

  /// The cover arts to try, best first.
  ///
  /// The resolve carries the extractor's own sizes, so it leads. The track's
  /// carried thumbnails are only a fallback: a search-time URL was chosen for
  /// a row (and under `dataSave` it is the smallest image the item has), so it
  /// must never outrank a real cover. Both lists share the same widest-first
  /// order and are deduplicated, then capped at four so a download that cannot
  /// get its artwork still fails fast.
  List<String> _artworkCandidates(ResolvedAudio resolved, FathomTrack track) {
    final candidates = <String>[];
    final seen = <String>{};

    void add(String? url) {
      if (url == null || url.isEmpty) return;
      if (!seen.add(url)) return;
      candidates.add(url);
    }

    for (final uri in resolved.artworks) {
      add(uri.toString());
    }
    add(track.artworkUrl);
    for (final url in rankedThumbnails(track.thumbUris)) {
      add(url);
    }
    add(track.thumbUri?.toString());
    return candidates.take(4).toList(growable: false);
  }

  /// Downloads the first candidate that answers with real image bytes.
  ///
  /// A candidate is allowed 15 seconds to connect, the same bound the artwork
  /// cache uses for a row thumbnail. `maxresdefault` is commonly absent, so a
  /// failed candidate is an ordinary step down the list, not a failed download:
  /// the file is still saved without a cover if none of them answers.
  Future<File?> _downloadArtwork(
      List<String> candidates, String videoId) async {
    for (final url in candidates.take(4)) {
      final bytes = await _fetchArtworkBytes(url);
      if (bytes == null || bytes.isEmpty) continue;

      // The cache is the library's fallback art for the finished file, so the
      // bytes have to land there before the save returns and the rescan
      // starts. Keeping them here costs nothing: they are already in hand.
      FathomArtCache.instance.remember(videoId, bytes);

      try {
        final file = File('${Directory.systemTemp.path}/art-$videoId.jpg');
        await file.writeAsBytes(bytes, flush: true);
        return file;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<Uint8List?> _fetchArtworkBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) return null;
      final bytes = await consolidateHttpClientResponseBytes(res);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      // A missing thumbnail must never fail the download it belongs to.
      return null;
    } finally {
      client.close(force: true);
    }
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
    unawaited(cancelDownloadNotification(videoId: videoId));
    _syncEntries();
    notifyListeners();
  }

  Future<File> _fetch(Uri address, String videoId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final part = File('${Directory.systemTemp.path}/fathom-dl-$videoId.part');
    try {
      // Probe first: a range request for the first byte reports the whole
      // file's length in `Content-Range`, while a plain GET would commit to
      // the throttled single-stream transfer before its size is known.
      final total = await _probeTotal(address);
      var chunked = false;
      if (total != null && total > kDownloadChunkThresholdBytes) {
        chunked = await _fetchChunked(client, address, part, total, videoId);
      }
      if (!chunked) {
        await _fetchSequential(client, address, part, videoId);
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

  /// Asks for the first byte and reads the file's length from `Content-Range`.
  ///
  /// HEAD is not usable against googlevideo: it does not reliably report the
  /// body length, so the probe has to be a ranged GET. A server that ignores
  /// the range answers 200 with no `Content-Range`, which returns null and
  /// leaves the caller with the sequential path; the body is dropped rather
  /// than drained so that case costs one request, not a second copy.
  Future<int?> _probeTotal(Uri address) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(address);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close();
      final total = _totalFromContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      if (total != null) {
        // A 206 carries exactly one byte, so reading it lets the socket close
        // without keeping a half-read response alive.
        try {
          await response.drain<void>();
        } catch (_) {}
      } else {
        try {
          await response.listen(null).cancel();
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The total size a `Content-Range` header names, or null when it does not.
  static int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    final total = int.tryParse(header.substring(slash + 1).trim());
    return (total == null || total <= 0) ? null : total;
  }

  /// Downloads [total] bytes as bounded ranges, or returns false to fall back.
  ///
  /// Up to [kDownloadChunkConcurrency] ranges are in flight at once, each
  /// written at its own offset through one [RandomAccessFile]. A failure is
  /// retried once and then abandons chunking for the whole transfer: a server
  /// that refuses the ranges the probe suggested would otherwise fail every
  /// chunk in turn. The sequential path truncates the file, so a partial
  /// chunked attempt never reaches the tagger.
  Future<bool> _fetchChunked(
    HttpClient client,
    Uri address,
    File part,
    int total,
    String videoId,
  ) async {
    final ranges = planDownloadRanges(total);
    if (ranges.length < 2) return false;

    RandomAccessFile out;
    try {
      out = await part.open(mode: FileMode.write);
    } catch (_) {
      return false;
    }

    var next = 0;
    var written = 0;
    var lastNotified = 0.0;
    var failed = false;
    Future<void> writes = Future.value();

    void report() {
      final fraction = (written / total).clamp(0.0, 1.0);
      if (fraction - lastNotified < 0.01 && fraction < 1.0) return;
      lastNotified = fraction;
      _progress[videoId] = fraction;
      notifyListeners();
      unawaited(updateDownloadProgress(
        videoId: videoId,
        title: _currentTrackTitleFor(videoId) ?? '',
        progress: (fraction * 100).round(),
      ));
    }

    Future<void> fetchOne(DownloadRange range) async {
      Uint8List bytes;
      try {
        bytes = await _readRange(client, address, range);
      } on _RangeUnsupported {
        rethrow;
      } catch (_) {
        bytes = await _readRange(client, address, range);
      }

      // Writes are serialised through one chain: a shared file handle makes
      // seek-then-write two operations, and two ranges interleaving them would
      // put bytes at the wrong offsets. Downloads stay concurrent; only the
      // short write step waits its turn.
      writes = writes.then((_) async {
        if (failed) return;
        await out.setPosition(range.start);
        await out.writeFrom(bytes);
        written += bytes.length;
        report();
      });
    }

    Future<void> worker() async {
      while (!failed) {
        final index = next++;
        if (index >= ranges.length) return;
        try {
          await fetchOne(ranges[index]);
        } catch (_) {
          failed = true;
          return;
        }
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < kDownloadChunkConcurrency; i++) worker(),
      ]);
      // Writes are queued behind the fetches, so wait for the chain before
      // deciding what is on disk.
      await writes;
    } finally {
      await out.close();
    }

    if (!failed && written == total) {
      report();
      return true;
    }

    part.delete().ignore();
    _progress[videoId] = 0.0;
    return false;
  }

  /// Fetches one byte range, or refuses to read it when Range was ignored.
  Future<Uint8List> _readRange(
    HttpClient client,
    Uri address,
    DownloadRange range,
  ) async {
    final request = await client.getUrl(address);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${range.start}-${range.end}',
    );
    final response = await request.close();
    if (response.statusCode == HttpStatus.ok) {
      // The server sent the whole file for a ranged request. Reading one of
      // these per chunk would fetch the file several times over, so abandon
      // chunking instead of paying that.
      try {
        await response.listen(null).cancel();
      } catch (_) {}
      throw const _RangeUnsupported();
    }
    if (response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Audio server said ${response.statusCode}');
    }

    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      throw HttpException('Audio server returned no bytes for a range');
    }
    return bytes;
  }

  /// The original single-stream transfer, used for small files and as the
  /// fallback when this server does not serve the ranges the probe implied.
  Future<void> _fetchSequential(
    HttpClient client,
    Uri address,
    File part,
    String videoId,
  ) async {
    _progress[videoId] = 0.0;
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
            unawaited(updateDownloadProgress(
              videoId: videoId,
              title: _currentTrackTitleFor(videoId) ?? '',
              progress: (fraction * 100).round(),
            ));
          }
        }
      }
      await out.flush();
    } finally {
      await out.close();
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
