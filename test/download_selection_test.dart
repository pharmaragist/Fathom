import 'package:flutter_test/flutter_test.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';

import 'package:fathom/services/yt_source.dart';

/// The extractor hands over every audio-only stream with a format suffix and
/// a bitrate. These tests pin the download's choice: AAC/m4a first (it is the
/// container the native tag writer can rewrite), highest bitrate within that,
/// and the highest bitrate of anything else only when there is no m4a at all.
AudioOnlyStream _stream(
  String id, {
  String? url,
  int bitrate = 1,
  String? suffix,
}) =>
    AudioOnlyStream(
      url: url ?? 'https://example.invalid/$id',
      averageBitrate: bitrate,
      formatSuffix: suffix,
    );

void main() {
  group('pickAudioStream', () {
    test('takes the highest-bitrate m4a, not the first or the lowest', () {
      final streams = [
        _stream('low', bitrate: 48, suffix: 'm4a'),
        _stream('medium', bitrate: 128, suffix: 'm4a'),
        _stream('high', bitrate: 256, suffix: 'm4a'),
      ];

      expect(pickAudioStream(streams)?.url, 'https://example.invalid/high');
    });

    test('prefers a taggable m4a over a higher-bitrate webm', () {
      // The m4a is the only container Fathom can write title/artist/cover
      // into, and a file without tags is what MediaStore describes by its
      // file name. The choice is therefore about the container first: a
      // slightly larger Opus track would be untaggable here.
      final streams = [
        _stream('opus', bitrate: 160, suffix: 'webm'),
        _stream('aac', bitrate: 128, suffix: 'm4a'),
      ];

      expect(pickAudioStream(streams)?.url, 'https://example.invalid/aac');
    });

    test('falls back to the highest bitrate when no m4a exists', () {
      final streams = [
        _stream('low-opus', bitrate: 50, suffix: 'webm'),
        _stream('high-opus', bitrate: 160, suffix: 'webm'),
        _stream('low-ogg', bitrate: 48, suffix: 'ogg'),
      ];

      expect(
          pickAudioStream(streams)?.url, 'https://example.invalid/high-opus');
    });

    test('skips an address-less stream so it cannot shadow a usable one', () {
      final streams = [
        _stream('broken', url: '', bitrate: 999, suffix: 'm4a'),
        _stream('usable', bitrate: 128, suffix: 'm4a'),
      ];

      expect(pickAudioStream(streams)?.url, 'https://example.invalid/usable');
    });

    test('returns null when nothing can be downloaded', () {
      expect(pickAudioStream(const []), isNull);
      expect(
        pickAudioStream([_stream('broken', url: '', suffix: 'm4a')]),
        isNull,
      );
    });
  });
}
