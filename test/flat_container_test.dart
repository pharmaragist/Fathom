import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/common/colors.dart';
import 'package:fathom/components/glass.dart';

/// Settings sections and the equalizer cards render as outlines: the page has
/// to show through the body, because their content already defines itself with
/// rules. These tests pin the two things that makes true — no fill and a
/// visible 1px hairline border — and that the filled form still paints.
void main() {
  Future<BoxDecoration> decorationFor(
    WidgetTester tester, {
    required bool filled,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body:
              FlatContainer(filled: filled, child: const SizedBox(height: 20)),
        ),
      ),
    );
    await tester.pump();
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('an outline-only card has no fill and one hairline border',
      (tester) async {
    final decoration = await decorationFor(tester, filled: false);

    expect(decoration.color, isNull);
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isNotNull);
    expect(decoration.border!.top.width, 1);
    expect(decoration.border!.top.color, FathomColors.hairline);
  });

  testWidgets('the filled form still paints a body', (tester) async {
    final decoration = await decorationFor(tester, filled: true);

    expect(decoration.color, isNotNull);
  });
}
