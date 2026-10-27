import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';

import '../models/ytmusic.dart';

/// Which thumbnail resolution a search asks for: only how much a row may
/// download, since the extractor returns every size and the caller picks.
enum YtQuality { low, high }

/// One item's audio address plus the cover-art candidates for its file; both
/// come from one resolve call, so splitting them would double the round trips.
@immutable
class ResolvedAudio {
  const ResolvedAudio({required this.audio, this.artworks = const []});

  /// The media address to download from. It expires within hours: use it at
  /// once, never store it.
  final Uri audio;

  /// The cover-art URLs the item carries, widest first, at most four.
  ///
  /// The largest preset is not guaranteed to exist, so the caller tries these in
  /// order and keeps the first that returns bytes.
  final List<Uri> artworks;

  /// The best candidate, derived so it cannot disagree with [artworks].
  Uri? get artwork => artworks.isEmpty ? null : artworks.first;
}

/// Picks the audio-only stream a download should fetch.
///
/// Never a muxed `videoStreams` entry: that is video Fathom would discard.
/// Within `audioOnlyStreams` the choice is the highest-bitrate `m4a`, the one
/// container the native metadata writer can tag without re-encoding. Only an
/// item with no m4a falls back to the best stream of any format, which keeps
/// MediaStore columns alone. Entries with no address are skipped.
AudioOnlyStream? pickAudioStream(List<AudioOnlyStream> streams) {
  AudioOnlyStream? bestAac;
  AudioOnlyStream? bestAny;

  for (final stream in streams) {
    final url = stream.url;
    if (url == null || url.isEmpty) continue;

    if (bestAny == null || stream.averageBitrate > bestAny.averageBitrate) {
      bestAny = stream;
    }
    if (stream.formatSuffix == 'm4a' &&
        (bestAac == null || stream.averageBitrate > bestAac.averageBitrate)) {
      bestAac = stream;
    }
  }

  return bestAac ?? bestAny;
}

/// The remote music source: a fetcher, not a streamer.
///
/// Nothing remote is playable. An item becomes music only after [resolve] and
/// `FathomDownloads` file it. There is deliberately no "playable URL" method: a
/// live address expires and is what forces signature deciphering.
abstract class FathomYtSource {
  /// Prepares the extractor. Safe to call repeatedly; the work happens once.
  Future<void> initialize();

  bool get isReady;

  /// Why [initialize] failed, or null while the extractor is usable.
  ///
  /// This describes the source, not one fetch: a single unresolvable track is
  /// reported through [lastResolveError], never here.
  String? get error;

  /// Why the most recent [resolve] returned null, or null when it succeeded.
  ///
  /// [resolve] answers with null rather than throwing, so this is the only place
  /// the reason survives; a caller that drops it leaves only "Could not save".
  String? get lastResolveError;

  /// Clears the remembered failure and retries, for an error panel's action.
  Future<void> retry();

  /// Remote search results. Callers that care about a superseded search must
  /// guard on their own token; this stream has no notion of one.
  Stream<YtItem> search(
    String query, {
    required int limit,
    required YtQuality quality,
  });

  /// Resolves one item's direct media address and the best cover art for the
  /// file it will become.
  ///
  /// The caller downloads immediately and never stores the address, which
  /// expires within hours. Null means the address could not be resolved (an
  /// ordinary outcome) and [lastResolveError] says why. The artwork is advisory
  /// but free, so dropping it leaves only the row-sized search URL.
  Future<ResolvedAudio?> resolve(String videoId);
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
  /// Chosen by the width the URL serves, never by list position: the
  /// extractor's list is unsorted, so "first" and "last" are arbitrary. A
  /// thrifty search asks for the small end and a full one for a row-sized
  /// image — neither wants YouTube's 1280px original, because a list row
  /// decodes it and throws almost all of it away.
  Uri? _thumbFor(StreamInfoItem item, YtQuality quality) {
    final chosen = pickThumbnail(
      item.thumbnails,
      maxWidth:
          quality == YtQuality.low ? kThumbThriftyMaxWidth : kThumbRowMaxWidth,
    );
    return chosen == null ? null : Uri.tryParse(chosen);
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
        thumbUris: item.thumbnails,
      );
    }
  }

  /// Resolves one item's audio address and its best cover art together.
  ///
  /// One round trip, not two: `VideoExtractor.getStream` already returns the
  /// video's own metadata — including every thumbnail size — alongside the
  /// streams, so reading both out of it costs nothing extra. That is what makes
  /// a download's artwork free as well as correct: the alternative was reusing
  /// the search-time URL, which is chosen for a list row and, with `dataSave`
  /// on, is the smallest image the item has.
  ///
  /// Null means the address could not be resolved, which is an ordinary
  /// outcome; [lastResolveError] says why. Artwork is advisory: an item whose
  /// thumbnails are missing still resolves, with no [ResolvedAudio.artworks].
  @override
  Future<ResolvedAudio?> resolve(String videoId) async {
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
      // The download pipeline rewrites only the mp4 metadata boxes and never
      // re-encodes, so an AAC track is the one that keeps its container and can
      // carry tags. An OGG track has no tagger here, so it is the fallback and
      // relies on the MediaStore row alone.
      final stream = pickAudioStream(video.audioOnlyStreams);
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

      final audio = Uri.tryParse(url);
      if (audio == null) {
        _resolveError =
            'YouTube returned an audio address Fathom could not read';
        return null;
      }

      _resolveError = null;
      // Ordered rather than a single choice: the largest preset is not
      // guaranteed to exist for every video, so the download needs the next
      // size down as a fallback. Four candidates is enough to cover the full
      // set — maxres, sd, hq, mq — without turning a failed fetch into a long
      // series of requests.
      final artworks = rankedThumbnails(video.videoInfo.thumbnails)
          .map(Uri.tryParse)
          .whereType<Uri>()
          .take(4)
          .toList(growable: false);
      return ResolvedAudio(audio: audio, artworks: artworks);
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
