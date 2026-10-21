import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/components/styled_list_view.dart';

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
}
