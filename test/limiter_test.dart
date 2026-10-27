import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/common/player.dart';

void main() {
  test('a flat curve predicts no boost', () {
    expect(maxEqBoost(const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), 0);
  });

  test('a cut-only curve predicts no boost', () {
    expect(maxEqBoost(const [-1, -2, -3.5, -12, 0, -1, -2, -3, -4, -5]), 0);
  });

  test('the largest positive gain is the predicted boost', () {
    expect(maxEqBoost(const [-2, 0, 1.5, 7, 3, -1, 0, 0, 0, 0]), 7);
  });

  test('a later band does not depend on order', () {
    expect(maxEqBoost(const [0, 0, 0, 0, 0, 0, 0, 0, 0, 7]), 7);
  });
}
