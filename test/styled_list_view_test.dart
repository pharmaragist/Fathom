import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/components/styled_list_view.dart';

/// A row whose element state is observable, so a test can tell a moved element
/// from a replaced one.
class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.label});

  final String label;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Text(widget.label);
  }
}

/// The list fades both ends rather than cutting rows off against the header and
/// the rail. These tests cover the two things that are easy to get wrong: the
/// mask actually being applied, and the degenerate case of a viewport too short
/// to hold both ramps.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  StyledListView<String> list({
    double topInset = 4.0,
    double bottomInset = 150.0,
  }) =>
      StyledListView<String>(
        items: const ['a', 'b', 'c'],
        accent: const Color(0xFFDC8666),
        topInset: topInset,
        bottomInset: bottomInset,
        labelFor: (_) => null,
        itemBuilder: (context, item, index, height) => SizedBox(
          height: height,
          child: Text(item),
        ),
      );

  testWidgets('fades both ends of the list', (tester) async {
    await tester.pumpWidget(wrap(list()));
    await tester.pumpAndSettle();

    // A mask is what turns the blunt edge into a fade. Without it the rows meet
    // the header and the rail flush.
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets(
      'applies the mask after blending, so a translucent row fades '
      'from where it already is', (tester) async {
    await tester.pumpWidget(wrap(list()));
    await tester.pumpAndSettle();

    final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    // `srcIn` multiplies the child's own alpha by the shader's. Anything else
    // would first force already-animating rows opaque.
    expect(mask.blendMode, BlendMode.dstIn);
  });

  testWidgets(
      'leaves the list unfaded when the viewport cannot hold both '
      'ramps', (tester) async {
    // A viewport this short would have the two fades overlap, which would make
    // the middle of the list invisible. Degenerating to no mask is the honest
    // failure: a hard edge is better than hidden content.
    await tester.pumpWidget(
      wrap(
        SizedBox(
          height: 40,
          child: list(topInset: 4, bottomInset: 150),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNothing);
    // The list is still there and still readable.
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('keeps the scrollbar outside the fade', (tester) async {
    await tester.pumpWidget(wrap(list()));
    await tester.pumpAndSettle();

    // The letter label intentionally overhangs the list when scrubbing, so the
    // mask must cover the scrolling rows only.
    final mask = find.byType(ShaderMask);
    expect(
      find.descendant(of: mask, matching: find.byType(CustomScrollView)),
      findsOneWidget,
    );
  });

  testWidgets('survives a viewport shorter than the scrollbar thumb floor',
      (tester) async {
    // The thumb has a legibility floor of 56px, and clamping to it on a track
    // shorter than that puts the lower bound above the upper one, which throws
    // and takes the whole list down. Reachable through a small window, an open
    // keyboard, or split screen.
    await tester.pumpWidget(
      wrap(SizedBox(height: 40, child: list())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('a'), findsOneWidget);
  });

  /// A keyed list that reuses row widgets the way the library page does.
  ///
  /// The reuse is what lets the test distinguish an element that moved from one
  /// that was rebuilt: an identical child widget short-circuits the rebuild.
  Widget keyedList(
    List<String> items,
    ScrollController controller,
    Map<String, Widget> rows, {
    String? Function(int index)? sectionFor,
  }) {
    return wrap(
      StyledListView<String>(
        items: items,
        scrollController: controller,
        accent: const Color(0xFFDC8666),
        keyFor: (i) => ValueKey('row-${items[i]}'),
        labelFor: (_) => null,
        sectionFor: sectionFor,
        initialItemHeight: 80,
        minItemHeight: 80,
        maxItemHeight: 80,
        itemBuilder: (context, item, index, height) => rows.putIfAbsent(
          item,
          () => _Probe(key: ValueKey('probe-$item'), label: item),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester, String item) {
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(ValueKey('row-$item')),
        matching: find.byType(Opacity),
      ),
    );
    return opacity.opacity;
  }

  testWidgets('inserting a keyed row keeps survivors and the scroll offset',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var items = [for (var i = 0; i < 40; i++) 'row $i'];
    final rows = <String, Widget>{};

    await tester.pumpWidget(keyedList(items, scroll, rows));
    await tester.pumpAndSettle();
    scroll.jumpTo(800);
    await tester.pump();

    final offset = scroll.offset;
    final probe = find.byKey(const ValueKey('probe-row 12'));
    expect(probe, findsOneWidget);
    final stateBefore = tester.state<_ProbeState>(probe);
    expect(stateBefore.buildCount, 1);

    items = ['new row', ...items];
    await tester.pumpWidget(keyedList(items, scroll, rows));
    await tester.pump();

    // A one-row insert must not move the viewport or replace the rows below
    // it.
    expect(scroll.offset, offset);
    expect(tester.state<_ProbeState>(probe), same(stateBefore));
    expect(stateBefore.buildCount, 1);
  });

  testWidgets('an insert animates the new row and not the survivors',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var items = [for (var i = 0; i < 8; i++) 'row $i'];
    final rows = <String, Widget>{};

    await tester.pumpWidget(keyedList(items, scroll, rows));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'row 3'), 1.0);

    items = ['new row', ...items];
    await tester.pumpWidget(keyedList(items, scroll, rows));
    await tester.pump(const Duration(milliseconds: 16));

    // The row that was already there stays fully visible; only the arriving
    // one runs the entrance.
    expect(opacityOf(tester, 'row 3'), 1.0);
    expect(opacityOf(tester, 'new row'), lessThan(1.0));

    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'new row'), 1.0);
  });

  testWidgets('removing a keyed row does not replay the survivors',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var items = [for (var i = 0; i < 8; i++) 'row $i'];
    final rows = <String, Widget>{};

    await tester.pumpWidget(keyedList(items, scroll, rows));
    await tester.pumpAndSettle();

    items = items.sublist(1);
    await tester.pumpWidget(keyedList(items, scroll, rows));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byKey(const ValueKey('row-row 1')), findsOneWidget);
    expect(opacityOf(tester, 'row 1'), 1.0);
  });

  testWidgets('a keyed insert keeps state across a section boundary',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var items = [
      for (var i = 0; i < 5; i++) 'device $i',
      for (var i = 0; i < 5; i++) 'youtube $i',
    ];
    final rows = <String, Widget>{};
    String? section(int i) =>
        items[i].startsWith('device') ? 'On device' : 'YouTube';

    await tester.pumpWidget(
      keyedList(items, scroll, rows, sectionFor: section),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(240);
    await tester.pump();

    final probe = find.byKey(const ValueKey('probe-youtube 2'));
    expect(probe, findsOneWidget);
    final before = tester.state<_ProbeState>(probe);

    items = ['device new', ...items];
    await tester.pumpWidget(
      keyedList(items, scroll, rows, sectionFor: section),
    );
    await tester.pump();

    // The second section's start moved by one; the row's index within that
    // section did not, which is what findChildIndexCallback has to use.
    expect(tester.state<_ProbeState>(probe), same(before));
    expect(scroll.offset, 240);
  });

  Widget stagedList(List<double> heights) => wrap(
        StyledListView<String>(
          items: const ['a', 'b', 'c'],
          accent: const Color(0xFFDC8666),
          zoomStages: const [38.0, 64.0, 90.0, 118.0],
          initialItemHeight: 90.0,
          labelFor: (_) => null,
          itemBuilder: (context, item, index, height) {
            heights.add(height);
            return SizedBox(height: height, child: Text(item));
          },
        ),
      );

  Future<void> doubleTapRow(WidgetTester tester) async {
    await tester.tap(find.text('a'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
  }

  testWidgets('double tap cycles every zoom stage and wraps', (tester) async {
    final heights = <double>[];
    await tester.pumpWidget(stagedList(heights));
    await tester.pumpAndSettle();

    expect(heights.last, 90);

    heights.clear();
    await doubleTapRow(tester);
    expect(heights.last, 118);

    heights.clear();
    await doubleTapRow(tester);
    expect(heights.last, 38, reason: 'the largest stage wraps to the smallest');

    heights.clear();
    await doubleTapRow(tester);
    expect(heights.last, 64);

    heights.clear();
    await doubleTapRow(tester);
    expect(heights.last, 90);
  });

  testWidgets('a pinch follows the finger, then snaps to the nearest stage',
      (tester) async {
    final heights = <double>[];
    await tester.pumpWidget(stagedList(heights));
    await tester.pumpAndSettle();

    final first = await tester.startGesture(
      const Offset(100, 200),
      pointer: 1,
    );
    final second = await tester.startGesture(
      const Offset(200, 200),
      pointer: 2,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await first.moveTo(const Offset(70, 200));
    await second.moveTo(const Offset(260, 200));
    await tester.pump(const Duration(milliseconds: 16));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    // 90 * 1.9 is 171, clamped to 118 and therefore already a stage.
    expect(heights.last, 118);
  });
}
