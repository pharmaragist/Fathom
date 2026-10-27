import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/components/track_text_morph.dart';
import 'package:fathom/components/track_title_deck.dart';
import 'package:fathom/models/tracks.dart';

/// The title/artist pair is the second half of the library-to-Now-Playing
/// shared element. These tests cover the two things that can be checked
/// without a full route flight: the pure style/gap interpolation, and which
/// pair in the deck carries the tag.
void main() {
  FathomTrack track(int id, String title, String artist) => FathomTrack(
        id: id,
        title: title,
        artist: artist,
        uri: 'content://media/external/audio/media/$id',
        origin: TrackOrigin.device,
      );

  final a = track(1, 'First', 'Artist A');
  final b = track(2, 'Second', 'Artist B');
  final c = track(3, 'Third', 'Artist C');

  const rowTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: Color(0xFF111111),
  );
  const rowArtist = TextStyle(
    fontSize: 12,
    color: Color(0xFF555555),
  );
  const pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: Color(0xFFEEEEEE),
  );
  const pageArtist = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    color: Color(0xFFBBBBBB),
  );

  final source = TrackTextMorph(
    title: 'Second',
    artist: 'Artist B',
    titleStyle: rowTitle,
    artistStyle: rowArtist,
  );
  final destination = TrackTextMorph(
    title: 'Second',
    artist: 'Artist B',
    titleStyle: pageTitle,
    artistStyle: pageArtist,
    gap: 2,
  );

  test('the lerp at t=0 is the source pair', () {
    final frame = lerpTrackTextMorph(source, destination, 0);

    expect(frame.titleStyle.fontSize, 16);
    expect(frame.titleStyle.fontWeight, FontWeight.w600);
    expect(frame.artistStyle.fontSize, 12);
    expect(frame.gap, 4);
  });

  test('the lerp at t=1 is the destination pair', () {
    final frame = lerpTrackTextMorph(source, destination, 1);

    expect(frame.titleStyle.fontSize, 22);
    expect(frame.titleStyle.fontWeight, FontWeight.w700);
    expect(frame.artistStyle.fontSize, 20);
    expect(frame.artistStyle.fontWeight, FontWeight.w400);
    expect(frame.gap, 2);
  });

  test('the lerp lands between the two pairs in the middle', () {
    final frame = lerpTrackTextMorph(source, destination, 0.5);

    expect(frame.titleStyle.fontSize, 19);
    expect(frame.artistStyle.fontSize, 16);
    expect(frame.gap, 3);
    expect(frame.title, 'Second');
    expect(frame.artist, 'Artist B');
  });

  Widget deck(ValueNotifier<double> progress, {String? heroTag}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: TrackTitleDeck(
              progress: progress,
              current: b,
              previous: a,
              next: c,
              heroTag: heroTag,
              titleStyle: pageTitle,
              artistStyle: pageArtist,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('heroTag exposes exactly one Hero, on the current pair',
      (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(deck(progress, heroTag: 'fathom-text-2'));

    expect(find.byType(Hero), findsOneWidget);
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'fathom-text-2');
    final child = hero.child;
    expect(child, isA<TrackTextMorph>());
    expect((child as TrackTextMorph).title, 'Second');

    expect(heroTagFinder('fathom-text-1'), findsNothing);
    expect(heroTagFinder('fathom-text-3'), findsNothing);
  });

  testWidgets('without heroTag the deck shows no Hero', (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(deck(progress));

    expect(find.byType(Hero), findsNothing);
  });
}

/// A Hero carrying [tag], so a test can look for one end of the pair without
/// counting the deck's whole tree.
Finder heroTagFinder(String tag) {
  return find
      .byWidgetPredicate((widget) => widget is Hero && widget.tag == tag);
}
