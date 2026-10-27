import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/tracks.dart';
import 'track_text_morph.dart';

/// The title/artist pair of the playing track, sliding with the cover deck.
///
/// Now Playing's cover carousel and the mini player both move their art and
/// their text as one card: when a skip lands, the pair does not snap to the new
/// values while the cover springs in. This is the same idea for the full-screen
/// title: three pairs — previous, current, next — positioned by the carousel's
/// own offset, so a drag moves the words with the art and a committed skip
/// carries them out in the direction the cover travelled.
///
/// The deck is driven by the *same* offset the carousel uses (0 at rest, ±1 for
/// a neighbouring slot), but it slides by its own distance: the words are
/// narrow and the covers are square, so translating the text by a full cover
/// spacing would fling it off before the fade could read. Same direction, same
/// curve, shorter travel.
class TrackTitleDeck extends StatelessWidget {
  const TrackTitleDeck({
    super.key,
    required this.progress,
    required this.current,
    required this.titleStyle,
    required this.artistStyle,
    this.previous,
    this.next,
    this.heroTag,
    this.slide = 38,
  });

  /// The carousel's live offset, in slots. 0 is the current track, and the
  /// sign matches the cover motion: a positive value has moved the deck left.
  final ValueListenable<double> progress;

  final FathomTrack current;
  final FathomTrack? previous;
  final FathomTrack? next;

  final TextStyle titleStyle;
  final TextStyle artistStyle;

  /// The shared-element tag on the current pair, or null when the deck is not
  /// a flight destination. Only the current pair is tagged: the neighbours are
  /// what a skip would reach, not something the route arrived from.
  final String? heroTag;

  /// How far a neighbouring pair sits from the current one, in logical pixels.
  final double slide;

  @override
  Widget build(BuildContext context) {
    // The neighbours are only distinct entries when the player actually has
    // one; a single-item queue (or repeat-one) hands the same track back on
    // both sides, and stacking it twice would paint the title on top of
    // itself at half opacity.
    final previous = this.previous?.id == current.id ? null : this.previous;
    final next = this.next?.id == current.id ? null : this.next;

    return ClipRect(
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, offset, _) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              _pair(0 - offset, current, isCurrent: true),
              if (previous != null)
                Positioned.fill(
                  child: _pair(-1 - offset, previous),
                ),
              if (next != null)
                Positioned.fill(
                  child: _pair(1 - offset, next),
                ),
            ],
          );
        },
      ),
    );
  }

  /// One slot. [rel] is its distance in slots from the viewport, so 0 is
  /// perfectly centred and ±1 is exactly one slide away and fully transparent.
  ///
  /// The current pair keeps the deck full width even though its morph column
  /// shrink-wraps: the deck is start-aligned, and a short title must not shift
  /// the whole stack off the cover's left edge.
  Widget _pair(
    double rel,
    FathomTrack track, {
    bool isCurrent = false,
  }) {
    final t = rel.abs().clamp(0.0, 1.0);
    final pair = TrackTextMorph(
      title: track.title,
      artist: track.artist,
      titleStyle: titleStyle,
      artistStyle: artistStyle,
      gap: 2,
    );
    final tag = isCurrent ? heroTag : null;
    return Transform.translate(
      offset: Offset(rel * slide, 0),
      child: Opacity(
        key: ValueKey('fathom-title-${track.id}'),
        opacity: 1 - t,
        child: SizedBox(
          width: double.infinity,
          child: tag == null
              ? pair
              : Hero(
                  tag: tag,
                  flightShuttleBuilder: trackTextHeroShuttle,
                  child: pair,
                ),
        ),
      ),
    );
  }
}
