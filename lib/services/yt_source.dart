import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';

import '../models/ytmusic.dart';

/// Which thumbnail resolution a search asks for.
///
/// The extractor returns every size the item carries and the caller picks, so
/// this is only about how much the row is allowed to download.
enum YtQuality { low, high }

/// The remote music source: a fetcher, not a streamer.
///
/// Fathom keeps nothing remote playable. A search finds items, and an item
/// becomes music only once [audioUri] has been used to fetch its bytes and
/// `FathomDownloads` has filed them on the device. There is deliberately no
/// "give me a URL I can play right now" method: a live stream address is the
/// fragile half of every YouTube client — it expires, it is throttled, and it
/// is what forces signature deciphering — and nothing here needs one.
abstract class FathomYtSource {
  /// Prepares the extractor. Safe to call repeatedly; the work happens once.
  Future<void> initialize();

  bool get isReady;

  /// Why [initialize] failed, or null while the extractor is usable.
  ///
  /// This describes the *source*, not one fetch: it is what the library page's
  /// error panel shows when a search cannot run at all. A single track that
  /// cannot be resolved does not write here — that would make one bad result
  /// look like the whole source being down — and is reported through
  /// [lastResolveError] instead.
  String? get error;

  /// Why the most recent [audioUri] call returned null, or null when it
  /// succeeded.
  ///
  /// [audioUri] answers with null rather than throwing, because a fetch that
  /// cannot be resolved is an ordinary outcome, not an exceptional one: the
  /// caller reports it as a failed download. That makes this the only place the
  /// reason survives, and a caller that drops it leaves the user with "Could
  /// not save" and nothing to act on.
  String? get lastResolveError;

  /// Clears the remembered failure and tries again, for an error panel's
  /// retry action.
  Future<void> retry();

  /// Remote search results, yielded progressively as the backend finds them.
  /// Callers that care about a superseded search should guard on their own
  /// token; this stream has no notion of one.
  Stream<YtItem> search(
    String query, {
    required int limit,
    required YtQuality quality,
  });

  /// The direct media address for one item, resolved at fetch time.
  ///
  /// The caller downloads from it immediately. It is never stored on a
  /// [FathomTrack], because it expires within hours. A null return means the
  /// address could not be resolved; [lastResolveError] says why.
  Future<Uri?> audioUri(String videoId);
}

class FathomYtMusic implements FathomYtSource {
  FathomYtMusic();

  Future<void>? _initFuture;
  bool _ready = false;
  String? _error;
  String? _resolveError;

  @override
  bool get isReady => _ready;

  @override
  String? get error => _error;

  @override
  String? get lastResolveError => _resolveError;

  /// The country whose catalogue to search, from the device locale.
  ///
  /// The extractor takes a language and a country rather than a market, so the
  /// best available answer is where the device already is.
  static String get deviceCountry {
    final code = ui.PlatformDispatcher.instance.locale.countryCode;
    final upper = code?.toUpperCase();
    return (upper != null && upper.length == 2) ? upper : 'US';
  }

  /// The language half of the same pair.
  static String get deviceLanguage {
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    return code.isEmpty ? 'en' : code;
  }

  @override
  Future<void> initialize() => _initFuture ??= _initialize();

  @override
  Future<void> retry() {
    _initFuture = null;
    return initialize();
  }

  Future<void> _initialize() async {
    try {
      // There is no handshake to perform: the extractor is ready once the JVM
      // side is loaded. Localisation is the one piece of setup that has to
      // happen before the first request, and its failure is not fatal, since a
      // wrong market still searches.
      await LocalizationExtractor.setLocalization(
        deviceLanguage,
        deviceCountry,
      );
      _ready = true;
      _error = null;
    } catch (e) {
      _ready = false;
      _error = e.toString();
    }
  }

  /// The thumbnail to show for one search item.
  ///
  /// The extractor lists every size the item carries, largest last, so a
  /// thrifty search takes the first entry and a full one the last.
  Uri? _thumbFor(StreamInfoItem item, YtQuality quality) {
    if (item.thumbnails.isEmpty) return null;
    final chosen =
        quality == YtQuality.low ? item.thumbnails.first : item.thumbnails.last;
    return Uri.tryParse(chosen);
  }

  @override
  Stream<YtItem> search(
    String query, {
    required int limit,
    required YtQuality quality,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await initialize();
    if (!_ready) return;

    // The extractor answers a page at a time rather than a progressive list,
    // so the stream is a shape the caller already understands, not a claim
    // that results arrive one by one.
    final page = await SearchExtractor.searchYoutubeMusic(trimmed, [
      SearchFilter.musicSongs.value,
    ]);

    var emitted = 0;
    for (final item in page.result.videos) {
      if (emitted >= limit) break;
      final videoId = item.id;
      if (videoId == null || videoId.isEmpty) continue;

      emitted++;
      yield YtItem(
        videoId: videoId,
        title: item.name ?? 'Untitled',
        artist: item.uploaderName ?? 'Unknown Artist',
        // The extractor reports length in whole seconds already.
        duration: item.duration,
        thumbUri: _thumbFor(item, quality),
      );
    }
  }

  @override
  Future<Uri?> audioUri(String videoId) async {
    if (videoId.isEmpty) {
      _resolveError = 'This result has no video id';
      return null;
    }
    await initialize();
    if (!_ready) {
      _resolveError =
          'The extractor is not ready: ${_error ?? 'unknown reason'}';
      return null;
    }

    try {
      final video = await VideoExtractor.getStream(
        'https://www.youtube.com/watch?v=$videoId',
      );
      // The download pipeline tags the file as m4a and ffmpeg copies the
      // stream, so an AAC track keeps the container it was written in. An OGG
      // stream would be remuxed into a container it does not belong in, so the
      // AAC track is preferred and only a video without one falls back.
      final stream = video.audioWithBestAacQuality;
      final url = stream?.url;
      if (url == null || url.isEmpty) {
        // The native side answers this call with an empty stream list rather
        // than an error, so a refusal to hand over a stream and a video that
        // genuinely has none are the same answer here. Say which one it is
        // without pretending to know more than that.
        _resolveError = video.audioOnlyStreams.isEmpty
            ? 'YouTube returned no audio stream for this track'
            : 'YouTube returned an audio stream with no address';
        return null;
      }
      _resolveError = null;
      return Uri.tryParse(url);
    } on PlatformException catch (e) {
      // A reCAPTCHA challenge is the one failure the package names, and it is
      // the one the user can actually do something about, so it says so
      // instead of reading like a network fault. Fathom does not wire the
      // package's navigator hook, so the challenge cannot be solved in-app.
      _resolveError = e.code == 'RECAPTCHA'
          ? 'YouTube asked for a captcha before it would hand this track over'
          : 'YouTube refused this track: ${e.message ?? e.code}';
      return null;
    } catch (e) {
      _resolveError = 'Could not resolve this track: $e';
      return null;
    }
  }
}
