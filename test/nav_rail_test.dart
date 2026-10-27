import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'package:fathom/components/nav_rail.dart';
import 'package:fathom/content.dart' show ShellPage;

void main() {
  testWidgets('the sort chip is still tappable inside the expanded search bar',
      (tester) async {
    final controller = TextEditingController();
    final query = ValueNotifier<String>('');
    final page = ValueNotifier<ShellPage>(ShellPage.library);
    var searchOpen = false;
    var sortTaps = 0;

    addTearDown(() {
      controller.dispose();
      query.dispose();
      page.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavRail(
              accent: const Color(0xFFFFFFFF),
              bottomSafe: 0,
              searchController: controller,
              query: query,
              onSearchChanged: (_) {},
              onSearchCleared: () {},
              onSearchOpenChanged: (open) => searchOpen = open,
              page: page,
              onGoTo: (_) {},
              sortLabel: 'Newest first',
              onSort: () => sortTaps++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(TablerIcons.search));
    await tester.pumpAndSettle();
    expect(searchOpen, isTrue);

    await tester.tap(find.text('Newest first'));
    await tester.pumpAndSettle();

    expect(sortTaps, 1);
  });
}
