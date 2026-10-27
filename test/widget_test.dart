import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/components/page_header.dart';

void main() {
  testWidgets('PageHeader shows its title and every trailing control',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PageHeader(
            title: 'Library',
            trailing: const [
              Icon(Icons.equalizer),
              Icon(Icons.settings),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Library'), findsOneWidget);
    expect(find.byIcon(Icons.equalizer), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('PageHeader without trailing controls is just the title',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(child: PageHeader(title: 'Library')),
      ),
    );

    expect(find.text('Library'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });
}
