import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/tracks.dart';
import 'package:fathom/models/ytmusic.dart';

/// The real shapes YouTube serves, including the ones that caused the bug.
///
/// These are the sizes the extractor actually returns for a music video: a
/// tiny square from the search payload, a couple of row-sized rewrites, and the
/// full-size original.
const _tiny = 'https://i.ytimg.com/vi/abc/default.jpg=w48-h48-l90-rj';
const _row120 = 'https://i.ytimg.com/vi/abc/mqdefault.jpg=w120-h120-l90-rj';
const _row320 = 'https://i.ytimg.com/vi/abc/mqdefault.jpg=w320-h320-l90-rj';
const _art1280 =
    'https://i.ytimg.com/vi/abc/maxresdefault.jpg=w1280-h720-l90-rj';

/// The plain ytimg presets, which carry their size only in the file name.
///
/// This is the shape that produced the broken cover: no `=w` suffix, so the
/// old reader called the width unknown and the picker took the first entry.
const _defaultPreset = 'https://i.ytimg.com/vi/abc/default.jpg';
const _mqPreset = 'https://i.ytimg.com/vi/abc/mqdefault.jpg';
const _hqPreset = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';
const _sdPreset = 'https://i.ytimg.com/vi/abc/sddefault.jpg';
const _maxresPreset = 'https://i.ytimg.com/vi/abc/maxresdefault.jpg';
const _hq720Preset = 'https://i.ytimg.com/vi/abc/hq720.jpg?sqp=xyz&rs=abc';
const _webpMaxPreset = 'https://i.ytimg.com/vi_webp/abc/maxresdefault.webp';
const _unknown = 'https://i.ytimg.com/vi/abc/not-a-known-preset.jpg';

void main() {
  group('thumbWidthOf', () {
    test('reads the width the URL encodes', () {
      expect(thumbWidthOf(_tiny), 48);
      expect(thumbWidthOf(_row320), 320);
      expect(thumbWidthOf(_art1280), 1280);
    });

    test('reads ytimg file-name presets', () {
      // A youtube thumbnail URL usually has no rewrite suffix at all, so the
      // file name is the only description of its size. Before this was read,
      // every ytimg URL looked unreadable and picking fell back to position.
      expect(thumbWidthOf(_maxresPreset), 1280);
      expect(thumbWidthOf(_hq720Preset), 1280);
      expect(thumbWidthOf(_webpMaxPreset), 1280);
      expect(thumbWidthOf(_sdPreset), 640);
      expect(thumbWidthOf(_hqPreset), 480);
      expect(thumbWidthOf(_mqPreset), 320);
      expect(thumbWidthOf(_defaultPreset), 120);

      for (final name in ['hq1', 'hq2', 'hq3', '1', '2', '3']) {
        expect(
          thumbWidthOf('https://i.ytimg.com/vi/abc/$name.jpg'),
          120,
          reason: '$name is one of the small player squares',
        );
      }
    });

    test('prefers an explicit rewrite over the file name', () {
      // The file name describes the original image; the suffix describes the
      // size actually being requested. When both exist the suffix is the truth.
      expect(thumbWidthOf('https://i.ytimg.com/vi/abc/maxresdefault.jpg=w320'),
          320);
    });

    test('reports null when the URL does not say', () {
      expect(thumbWidthOf(_unknown), isNull);
      expect(thumbWidthOf('https://example.invalid/cover.jpg'), isNull);
      expect(thumbWidthOf(''), isNull);
    });
  });

  group('pickThumbnail', () {
    test('takes the largest size that fits under the cap', () {
      // The cap is what separates a row from real cover art, so the answer has
      // to be the biggest image that does not exceed it — not the biggest
      // overall, which would waste the bandwidth the cap exists to save.
      final urls = [_tiny, _row120, _row320, _art1280];

      expect(pickThumbnail(urls, maxWidth: kThumbRowMaxWidth), _row320);
      expect(pickThumbnail(urls, maxWidth: kThumbArtMaxWidth), _art1280);
      expect(pickThumbnail(urls, maxWidth: kThumbThriftyMaxWidth), _row120);
    });

    test('picks the real cover art from plain ytimg presets', () {
      // This is the reported failure: a list of presets used to have no
      // readable widths, so the first URL won and a 120px square was embedded
      // as the file's cover.
      final urls = [_defaultPreset, _mqPreset, _hqPreset, _maxresPreset];

      expect(pickThumbnail(urls, maxWidth: kThumbArtMaxWidth), _maxresPreset);
      // A row can take 320 exactly, so mqdefault wins; when it is absent the
      // smallest above-cap preset is still better than no image.
      expect(pickThumbnail(urls, maxWidth: kThumbRowMaxWidth), _mqPreset);
      // Without a size at or below the cap the smallest available preset wins,
      // so hqdefault stands in for a row when mqdefault is missing.
      expect(
        pickThumbnail([_hqPreset, _maxresPreset], maxWidth: kThumbRowMaxWidth),
        _hqPreset,
      );
      expect(
        pickThumbnail(urls, maxWidth: kThumbThriftyMaxWidth),
        _defaultPreset,
      );
    });

    test('does not depend on the list order the extractor returns', () {
      // This is the bug: `thumbnails.last` was arbitrary because the native
      // side never sorts, so the same set could yield a 48px square for a row
      // that had room for 320. Every permutation has to agree.
      final urls = [_art1280, _tiny, _row320, _row120];
      final reversed = urls.reversed.toList();

      expect(
        pickThumbnail(urls, maxWidth: kThumbRowMaxWidth),
        pickThumbnail(reversed, maxWidth: kThumbRowMaxWidth),
      );
      expect(pickThumbnail(urls, maxWidth: kThumbRowMaxWidth), _row320);
    });

    test('accepts a size somewhat over the cap over none at all', () {
      // A cap that undercuts every size the item has must still return an
      // image: a smaller-than-asked thumbnail is a worse picture, but no
      // thumbnail at all is a broken one.
      expect(pickThumbnail([_row320, _art1280], maxWidth: 200), _row320);
    });

    test('falls back to an unreadable URL only when nothing else is usable',
        () {
      // A readable size always wins, whatever order it arrives in.
      expect(pickThumbnail([_unknown, _row320], maxWidth: 320), _row320);
      expect(pickThumbnail([_unknown], maxWidth: 320), _unknown);
    });

    test('returns null for an empty list', () {
      expect(pickThumbnail(const [], maxWidth: 320), isNull);
      expect(pickThumbnail(const [''], maxWidth: 320), isNull);
    });
  });

  group('rankedThumbnails', () {
    test('orders widest first', () {
      final ranked = rankedThumbnails([
        _defaultPreset,
        _maxresPreset,
        _mqPreset,
        _hqPreset,
      ]);

      expect(ranked, [_maxresPreset, _hqPreset, _mqPreset, _defaultPreset]);
    });

    test('puts unreadable sizes last and drops duplicates', () {
      // A cover-art download walks this list in order. A URL with no known
      // size is worth one try at the end, never a place ahead of a real preset.
      final ranked = rankedThumbnails([
        _unknown,
        _maxresPreset,
        _maxresPreset,
        _defaultPreset,
        '',
        _unknown,
      ]);

      expect(ranked, [_maxresPreset, _defaultPreset, _unknown]);
    });

    test('returns an empty list when there is nothing usable', () {
      expect(rankedThumbnails(const []), isEmpty);
      expect(rankedThumbnails(const ['', '']), isEmpty);
    });
  });

  group('FathomTrack.artworkUrl', () {
    FathomTrack remote(List<String> thumbUris, {Uri? thumbUri}) =>
        FathomTrack.yt(
          YtItem(
            videoId: 'abc',
            title: 'Song',
            artist: 'Artist',
            thumbUri: thumbUri,
            thumbUris: thumbUris,
          ),
        );

    test('asks for real cover art, not the row-sized thumbnail', () {
      // The file's tag outlives the app, so what it embeds must not be the
      // image chosen for a list row. With `dataSave` on that row image is the
      // smallest one the item has, which is exactly the "worst quality" the
      // download used to be stuck with.
      final track = remote(
        const [_tiny, _row320, _art1280],
        thumbUri: Uri.parse(_tiny),
      );

      expect(track.artworkUrl, _art1280);
    });

    test('picks maxresdefault from the plain ytimg presets', () {
      final track = remote(
        const [_defaultPreset, _mqPreset, _hqPreset, _maxresPreset],
        thumbUri: Uri.parse(_defaultPreset),
      );

      expect(track.artworkUrl, _maxresPreset);
    });

    test('still resolves cover art when the search kept only a tiny URL', () {
      // The whole point of carrying the full list: the row URL is deliberately
      // small, so the download has to pick again rather than reuse it.
      final track = remote(const [_tiny, _art1280], thumbUri: Uri.parse(_tiny));

      expect(track.artworkUrl, isNot(_tiny));
      expect(track.artworkUrl, _art1280);
    });

    test('falls back to the row thumbnail when no list was carried', () {
      // Older or partially-populated items have only the chosen URL, which is
      // still better than tagging the file with nothing.
      final track = remote(const [], thumbUri: Uri.parse(_row320));

      expect(track.artworkUrl, _row320);
    });

    test('is null when the item carries no artwork at all', () {
      expect(remote(const []).artworkUrl, isNull);
    });
  });
}
