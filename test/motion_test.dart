import 'dart:math' as math;

import 'package:fathom/common/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _peak(FathomSpring spring) {
  final simulation = spring.simulation(from: 0, to: 1);
  var peak = 0.0;
  for (var t = 0.0; !simulation.isDone(t) && t < 5; t += 1 / 120) {
    peak = math.max(peak, simulation.x(t));
  }
  return peak;
}

void main() {
  group('FathomSpring', () {
    test('response maps to the expected stiffness', () {
      const spring = FathomSpring(response: 0.4, dampingRatio: 0.8);
      final omega = 2 * math.pi / 0.4;
      expect(spring.stiffness, closeTo(omega * omega, 1e-9));
      expect(
        spring.description.damping,
        closeTo(2 * 0.8 * omega, 1e-6),
      );
    });

    test('a critically damped spring does not overshoot', () {
      expect(_peak(FathomMotion.standard), lessThanOrEqualTo(1.002));
      expect(_peak(FathomMotion.gentle), lessThanOrEqualTo(1.002));
    });

    test('the momentum spring overshoots only a little', () {
      final peak = _peak(FathomMotion.momentum);
      expect(peak, greaterThan(1.005));
      expect(peak, lessThan(1.05));
    });

    test('a simulation can resume from a moving value', () {
      final simulation = FathomMotion.momentum.simulation(
        from: 0.4,
        to: 1,
        velocity: 2,
      );
      expect(simulation.x(0), 0.4);
      expect(simulation.dx(0), 2);
    });
  });

  group('FathomSpringCurve', () {
    const curve = FathomSpringCurve();

    test('starts and ends at its endpoints', () {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    });

    test('decelerates without ever going backwards', () {
      var previous = 0.0;
      for (var i = 1; i <= 100; i++) {
        final value = curve.transform(i / 100);
        expect(value, greaterThanOrEqualTo(previous - 1e-9));
        previous = value;
      }
    });

    test('arrives faster than a straight line', () {
      expect(curve.transform(0.5), greaterThan(0.5));
    });
  });

  group('SpringValue', () {
    testWidgets('starts at the target unless told to animate on mount', (
      tester,
    ) async {
      var seen = double.nan;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SpringValue(
            value: 3,
            builder: (context, value) {
              seen = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, 3);
    });

    testWidgets('springs from zero when animateOnMount is set', (tester) async {
      var seen = double.nan;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SpringValue(
            value: 1,
            animateOnMount: true,
            spring: FathomMotion.gentle,
            builder: (context, value) {
              seen = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, 0);
      await tester.pumpAndSettle();
      expect(seen, closeTo(1, 0.001));
    });

    testWidgets('an immediate value snaps instead of travelling', (
      tester,
    ) async {
      var seen = double.nan;
      Widget build(double value) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: SpringValue(
            value: value,
            immediate: true,
            builder: (context, current) {
              seen = current;
              return const SizedBox.shrink();
            },
          ),
        );
      }

      await tester.pumpWidget(build(4));
      expect(seen, 4);
      await tester.pumpWidget(build(9));
      expect(seen, 9);
    });

    testWidgets('retargeting keeps the value already on screen',
        (tester) async {
      var seen = double.nan;
      Widget build(double value) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: SpringValue(
            value: value,
            builder: (context, current) {
              seen = current;
              return const SizedBox.shrink();
            },
          ),
        );
      }

      // Start at rest, then move: a spring that begins on its target has
      // nothing on screen to continue from.
      await tester.pumpWidget(build(0));
      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 120));
      final midway = seen;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1));

      await tester.pumpWidget(build(0));
      // The first frame of the new target starts from the presentation value,
      // not from the old target or from zero.
      expect(seen, closeTo(midway, 0.05));
    });
  });
}
