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

void main() {
  group('thumbWidthOf', () {
    test('reads the width the URL encodes', () {
      expect(thumbWidthOf(_tiny), 48);
      expect(thumbWidthOf(_row320), 320);
      expect(thumbWidthOf(_art1280), 1280);
    });

    test('reports null when the URL does not say', () {
      expect(thumbWidthOf('https://i.ytimg.com/vi/abc/default.jpg'), isNull);
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
      const noSize = 'https://i.ytimg.com/vi/abc/default.jpg';

      // A readable size always wins, whatever order it arrives in.
      expect(pickThumbnail([noSize, _row320], maxWidth: 320), _row320);
      expect(pickThumbnail([noSize], maxWidth: 320), noSize);
    });

    test('returns null for an empty list', () {
      expect(pickThumbnail(const [], maxWidth: 320), isNull);
      expect(pickThumbnail(const [''], maxWidth: 320), isNull);
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
