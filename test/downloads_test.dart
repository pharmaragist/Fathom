import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fathom/models/tracks.dart';
import 'package:fathom/models/ytmusic.dart';
import 'package:fathom/services/downloads.dart';
import 'package:fathom/services/yt_source.dart';

/// The downloads list is built from two records: the service's own view of the
/// work it still owes the user, and the manifest's view of what is on the
/// device. These tests cover the service's half — that a failure is reported
/// with its reason, that it can be retried, and that a dismissed failure does
/// not come back.
class _FakeSource implements FathomYtSource {
  _FakeSource({this.resolveError = 'YouTube refused this track'});

  /// What a resolve answers with. Null means the address could not be had.
  final String? resolveError;

  int resolveCalls = 0;

  @override
  bool get isReady => true;

  @override
  String? get error => null;

  @override
  String? get lastResolveError => resolveError;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> retry() async {}

  @override
  Stream<YtItem> search(
    String query, {
    required int limit,
    required YtQuality quality,
  }) =>
      const Stream<YtItem>.empty();

  @override
  Future<ResolvedAudio?> resolve(String videoId) async {
    resolveCalls++;
    return null;
  }
}

FathomTrack _remote(String videoId) => FathomTrack.yt(
      YtItem(videoId: videoId, title: 'Song $videoId', artist: 'Artist'),
    );

void main() {
  test('a failed download is listed with the reason it failed', () async {
    final downloads = FathomDownloads(
      source: _FakeSource(),
      onFinished: () {},
    );

    final ok = await downloads.download(_remote('abc'));

    expect(ok, isFalse);
    expect(downloads.entries, hasLength(1));
    final entry = downloads.entries.first;
    expect(entry.videoId, 'abc');
    expect(entry.state, DownloadState.failed);
    // The cause survives: a captcha and a track with no audio stream are not
    // the same failure, and the row says which one it was.
    expect(entry.failure, 'YouTube refused this track');
    expect(downloads.failureOf('abc'), 'YouTube refused this track');
  });

  test('a failure can be retried, and the retry clears the reason', () async {
    final source = _FakeSource();
    final downloads = FathomDownloads(source: source, onFinished: () {});

    await downloads.download(_remote('abc'));
    expect(downloads.entries.first.state, DownloadState.failed);

    await downloads.download(_remote('abc'));

    expect(source.resolveCalls, 2);
    expect(downloads.entries, hasLength(1));
    expect(downloads.entries.first.state, DownloadState.failed);
  });

  test('a dismissed failure leaves the list', () async {
    final downloads = FathomDownloads(
      source: _FakeSource(),
      onFinished: () {},
    );

    await downloads.download(_remote('abc'));
    expect(downloads.entries, hasLength(1));

    downloads.forget('abc');

    expect(downloads.entries, isEmpty);
    expect(downloads.failureOf('abc'), isNull);
    expect(downloads.stateOf('abc'), DownloadState.idle);
  });

  test('the list of fetched files starts empty and only holds ours', () async {
    final downloads = FathomDownloads(
      source: _FakeSource(),
      onFinished: () {},
    );

    expect(downloads.downloadedMediaIds, isEmpty);
    expect(downloads.isDownloadedDeviceTrack(7), isFalse);
  });

  test('the reason comes from the source, not a generic phrase', () async {
    final captcha = FathomDownloads(
      source: _FakeSource(resolveError: 'YouTube asked for a captcha'),
      onFinished: () {},
    );
    await captcha.download(_remote('abc'));
    expect(captcha.entries.first.failure, 'YouTube asked for a captcha');

    // With nothing to explain the failure, the row still says something better
    // than silence.
    final silent = FathomDownloads(
      source: _FakeSource(resolveError: null),
      onFinished: () {},
    );
    await silent.download(_remote('def'));
    expect(silent.entries.first.failure, 'No audio address for this track');
  });

  test('the manifest maps a fetched media id back to its remote item',
      () async {
    // The library only knows a finished download by its MediaStore id. The
    // artwork fallback has to walk back to the video id the cover was cached
    // under, so this reverse lookup is what connects the two records.
    SharedPreferences.setMockInitialValues({
      'downloads.manifest.v1': jsonEncode({'abc': 41, 'def': 42}),
    });

    final downloads = FathomDownloads(
      source: _FakeSource(),
      onFinished: () {},
    );
    await downloads.manifestReady;

    expect(downloads.videoIdForMediaId(41), 'abc');
    expect(downloads.videoIdForMediaId(42), 'def');
    expect(downloads.videoIdForMediaId(43), isNull);
    // -1 is "the file landed but the store did not name it", which is not an
    // id any track can carry.
    expect(downloads.videoIdForMediaId(-1), isNull);
    expect(downloads.downloadedMediaIds, unorderedEquals([41, 42]));
  });

  group('planDownloadRanges', () {
    test('splits an exact multiple without a zero-length tail', () {
      final ranges = planDownloadRanges(4 * kDownloadChunkBytes);

      expect(ranges, hasLength(4));
      expect(ranges.first.start, 0);
      expect(ranges.first.end, kDownloadChunkBytes - 1);
      expect(ranges.last.start, 3 * kDownloadChunkBytes);
      expect(ranges.last.end, 4 * kDownloadChunkBytes - 1);
      // Covering every byte exactly once is the property the transfer relies
      // on: a gap leaves a corrupt file and an overlap writes bytes twice.
      expect(
        ranges.fold<int>(0, (sum, range) => sum + range.length),
        4 * kDownloadChunkBytes,
      );
    });

    test('keeps the remainder in the last range', () {
      const total = 2 * kDownloadChunkBytes + 1234;
      final ranges = planDownloadRanges(total);

      expect(ranges, hasLength(3));
      expect(ranges.last.length, 1234);
      expect(ranges.last.end, total - 1);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].start, ranges[i - 1].end + 1);
      }
    });

    test('returns no ranges for an empty or invalid total', () {
      expect(planDownloadRanges(0), isEmpty);
      expect(planDownloadRanges(-1), isEmpty);
    });

    test('keeps a small file in one chunk', () {
      const total = 500 * 1024;
      final ranges = planDownloadRanges(total);

      expect(ranges, hasLength(1));
      expect(ranges.single.start, 0);
      expect(ranges.single.end, total - 1);
      expect(ranges.single.length, total);
    });

    test('a total that is exactly one chunk is one full range', () {
      final ranges = planDownloadRanges(kDownloadChunkBytes);

      expect(ranges, hasLength(1));
      expect(ranges.single.start, 0);
      expect(ranges.single.end, kDownloadChunkBytes - 1);
    });
  });
}
