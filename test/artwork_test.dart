import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/artwork.dart';

/// The artwork cache is the one place a download's cover art and a later
/// library row meet. These tests cover the read side that meeting needs: bytes
/// kept under a video id can be looked up without a thumbnail URL, because the
/// library only has the media id and the manifest's video id.
void main() {
  test('a remembered cover is available without a thumbnail URL', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final cache = FathomArtCache.instance;

    cache.remember('test-remembered-video', bytes);

    expect(await cache.forVideo('test-remembered-video', null), equals(bytes));
    expect(cache.cachedForVideo('test-remembered-video'), equals(bytes));
  });

  test('an unknown id has no cached cover', () {
    expect(
      FathomArtCache.instance.cachedForVideo('test-never-fetched-video'),
      isNull,
    );
  });

  test('empty artwork is not remembered as a cover', () {
    final cache = FathomArtCache.instance;

    cache.remember('test-empty-video', Uint8List(0));

    expect(cache.cachedForVideo('test-empty-video'), isNull);
  });
}
