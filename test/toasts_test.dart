import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fathom/common/settings.dart';
import 'package:fathom/common/toasts.dart';
import 'package:fathom/components/toast_layer.dart';

void main() {
  group('FathomToasts', () {
    test('keeps the newest toasts when the visible cap is exceeded', () {
      final toasts = FathomToasts();
      for (var i = 0; i < FathomToasts.maxVisible + 2; i++) {
        toasts.show('message $i');
      }

      expect(toasts.toasts, hasLength(FathomToasts.maxVisible));
      // The newest is the one worth keeping: the oldest were dropped.
      expect(
        toasts.toasts.map((t) => t.title),
        ['message 2', 'message 3', 'message 4'],
      );
    });

    test('dismiss removes only its own toast', () {
      final toasts = FathomToasts();
      final first = toasts.show('first');
      toasts.show('second');

      toasts.dismiss(first);

      expect(toasts.toasts.map((t) => t.title), ['second']);
    });

    test('dismiss is idempotent and safe for an unknown id', () {
      final toasts = FathomToasts();
      final id = toasts.show('only');

      toasts.dismiss(id);
      toasts.dismiss(id);
      toasts.dismiss(999);

      expect(toasts.toasts, isEmpty);
    });

    test('a toast carries its detail and dismissible flag', () {
      final toasts = FathomToasts();
      toasts.show(
        'Could not save',
        detail: 'YouTube asked for a captcha',
        tone: ToastTone.failure,
        dismissible: true,
      );

      final toast = toasts.toasts.single;
      expect(toast.title, 'Could not save');
      expect(toast.detail, 'YouTube asked for a captcha');
      expect(toast.tone, ToastTone.failure);
      expect(toast.dismissible, isTrue);
    });

    test('auto-dismisses after its duration', () async {
      final toasts = FathomToasts();
      toasts.show('brief', duration: const Duration(milliseconds: 20));

      expect(toasts.toasts, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(toasts.toasts, isEmpty);
    });

    test('a pending auto-dismiss does not fire after dispose', () async {
      final toasts = FathomToasts();
      toasts.show('brief', duration: const Duration(milliseconds: 20));
      toasts.dispose();

      // The delayed callback would otherwise call notifyListeners() on a
      // disposed notifier, which throws.
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
  });

  group('FathomToastLayer', () {
    /// Longer than any widget test runs, so an auto-dismiss timer is never the
    /// thing under assertion. The auto-dismiss path has its own unit test.
    const long = Duration(minutes: 5);

    setUp(() {
      // FathomSettings loads from SharedPreferences, so the mock backing store
      // has to exist before it is constructed.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Widget wrap(FathomToasts toasts, FathomSettings settings) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: toasts),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const MaterialApp(
            home: Scaffold(body: FathomToastLayer()),
          ),
        );

    /// Builds the layer with a real settings store, which is what the layer
    /// reads its accent from.
    Future<Widget> harness(FathomToasts toasts) async =>
        wrap(toasts, await FathomSettings.load());

    testWidgets('shows a title and its detail as separate lines',
        (tester) async {
      final toasts = FathomToasts();
      addTearDown(toasts.dispose);

      await tester.pumpWidget(await harness(toasts));
      toasts.show(
        'Could not save',
        detail:
            'YouTube asked for a captcha before it would hand this track over',
        tone: ToastTone.failure,
        duration: long,
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not save'), findsOneWidget);
      expect(
        find.text(
          'YouTube asked for a captcha before it would hand this track over',
        ),
        findsOneWidget,
      );

      toasts.clear();
    });

    testWidgets('keeps a dismissed card mounted until its exit finishes',
        (tester) async {
      final toasts = FathomToasts();
      addTearDown(toasts.dispose);

      await tester.pumpWidget(await harness(toasts));
      final id = toasts.show('going away', duration: long);
      await tester.pumpAndSettle();
      expect(find.text('going away'), findsOneWidget);

      toasts.dismiss(id);
      // One frame in, the exit is running, so the card must still be there.
      await tester.pump();
      expect(find.text('going away'), findsOneWidget);

      // Once the exit animation has run, the layer drops it.
      await tester.pumpAndSettle();
      expect(find.text('going away'), findsNothing);

      toasts.clear();
    });

    testWidgets('offers a close control only on a dismissible toast',
        (tester) async {
      final toasts = FathomToasts();
      addTearDown(toasts.dispose);

      await tester.pumpWidget(await harness(toasts));
      toasts.show('Downloading', dismissible: true, duration: long);
      toasts.show('Saved', duration: long);
      await tester.pumpAndSettle();

      // Only the long-running card gained the affordance.
      expect(find.byIcon(TablerIcons.x), findsOneWidget);

      toasts.clear();
    });

    testWidgets('taking hits only when a card offers a control',
        (tester) async {
      final toasts = FathomToasts();
      addTearDown(toasts.dispose);

      await tester.pumpWidget(await harness(toasts));
      toasts.show('Saved', duration: long);
      await tester.pumpAndSettle();

      // An ordinary toast must not swallow a tap meant for the page beneath.
      final layer = find.byType(FathomToastLayer);
      expect(
        find.descendant(of: layer, matching: find.byType(IgnorePointer)),
        findsOneWidget,
      );

      toasts.show('Downloading', dismissible: true, duration: long);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: layer, matching: find.byType(IgnorePointer)),
        findsNothing,
      );

      toasts.clear();
    });
  });
}
