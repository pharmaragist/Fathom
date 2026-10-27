import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/components/track_title_deck.dart';
import 'package:fathom/models/tracks.dart';

/// The title/artist pair under the Now Playing cover has to travel with the
/// cover deck, not snap. These tests cover the deck's own contract: at rest it
/// shows only the current pair, a partial drag brings in the neighbour in the
/// right direction, and a committed skip at ±1 has moved the old pair out.
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

  Widget host(ValueNotifier<double> progress) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: TrackTitleDeck(
                progress: progress,
                current: b,
                previous: a,
                next: c,
                titleStyle: const TextStyle(fontSize: 22),
                artistStyle: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      );

  testWidgets('at rest only the current pair is visible', (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(host(progress));
    await tester.pumpAndSettle();

    expect(_opacityFor(2).opacity, 1);
    expect(_opacityFor(2).opacity, 1);
    expect(_opacityFor(1).opacity, 0);
    expect(_opacityFor(3).opacity, 0);
  });

  testWidgets('a drag fades the neighbour in as it travels', (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(host(progress));
    await tester.pumpAndSettle();

    progress.value = 0.5;
    await tester.pump();

    expect(_opacityFor(2).opacity, closeTo(0.5, 0.01));
    expect(_opacityFor(3).opacity, closeTo(0.5, 0.01));
    expect(_opacityFor(1).opacity, 0);
  });

  testWidgets('a committed skip leaves the previous pair out', (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(host(progress));
    await tester.pumpAndSettle();

    progress.value = -1;
    await tester.pump();

    expect(_opacityFor(2).opacity, 0);
    expect(_opacityFor(1).opacity, 1);
  });

  testWidgets('the same track on both sides is not stacked twice',
      (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: TrackTitleDeck(
              progress: progress,
              current: a,
              previous: a,
              next: a,
              titleStyle: const TextStyle(fontSize: 22),
              artistStyle: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One pair, not three overlapping copies of it.
    expect(find.text('First'), findsOneWidget);
  });
}

/// The deck's own fade for one track's pair. It carries a key so the test
/// reads the deck's opacity rather than any outer widget that may also use
/// [Opacity].
Opacity _opacityFor(int id) {
  final finder = find.byKey(ValueKey('fathom-title-$id'));
  expect(finder, findsOneWidget);
  return finder.evaluate().single.widget as Opacity;
}
