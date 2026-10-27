import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../common/motion.dart';

/// The title/artist pair carried by a text hero.
///
/// Both ends of the flight use this widget as the [Hero] child, which is what
/// lets the shuttle read two comparable layouts: one ellipsized line each,
/// separated by [gap]. The library row and the Now Playing headline differ only
/// in their styles, so the flight interpolates those and nothing else.
class TrackTextMorph extends StatelessWidget {
  const TrackTextMorph({
    super.key,
    required this.title,
    required this.artist,
    required this.titleStyle,
    required this.artistStyle,
    this.gap = 4,
  });

  final String title;
  final String artist;
  final TextStyle titleStyle;
  final TextStyle artistStyle;

  /// Vertical space between the two lines.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        SizedBox(height: gap),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: artistStyle,
        ),
      ],
    );
  }
}

/// One frame of a text hero flight, [t] from the source (0) to the destination
/// (1).
///
/// Kept as a pure helper for callers that need a single interpolated frame;
/// the shuttle itself does not use it, because rebuilding two text layouts per
/// frame was the expensive half of the morph.
TrackTextMorph lerpTrackTextMorph(
  TrackTextMorph source,
  TrackTextMorph destination,
  double t,
) {
  return TrackTextMorph(
    title: destination.title,
    artist: destination.artist,
    titleStyle: TextStyle.lerp(source.titleStyle, destination.titleStyle, t)!,
    artistStyle:
        TextStyle.lerp(source.artistStyle, destination.artistStyle, t)!,
    gap: lerpDouble(source.gap, destination.gap, t)!,
  );
}

/// Flight shuttle for every text hero.
///
/// The two layouts are built once and their opacity is animated, rather than
/// lerping every text style and re-laying out two lines on every frame. The
/// destination also eases up from 96.5%, which supplies the resize the old
/// per-frame interpolation gave without a per-frame layout pass. The art hero
/// carries the spatial morph; this carries the words into their new type size.
Widget trackTextHeroShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final from = (fromHeroContext.widget as Hero).child;
  final to = (toHeroContext.widget as Hero).child;

  // Hero runs its value backwards on pop, so this is the flight's progress
  // from the outgoing end (0) to the incoming end (1).
  final entering = flightDirection == HeroFlightDirection.push
      ? animation
      : ReverseAnimation(animation);
  final leaving = ReverseAnimation(entering);

  return Material(
    type: MaterialType.transparency,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          FadeTransition(opacity: leaving, child: from),
          FadeTransition(
            opacity: entering,
            child: ScaleTransition(
              alignment: Alignment.centerLeft,
              scale: Tween<double>(begin: 0.965, end: 1.0).animate(
                CurvedAnimation(
                  parent: entering,
                  curve: const FathomSpringCurve(),
                ),
              ),
              child: to,
            ),
          ),
        ],
      ),
    ),
  );
}
