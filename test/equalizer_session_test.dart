import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/common/player.dart';

/// An Android audio effect is bound to one audio session. ExoPlayer recreates
/// that session when the audio sink changes, and the effect built for the old
/// id keeps accepting writes while processing nothing. These tests pin the rule
/// that turns that silent loss into a re-attach.
void main() {
  test('a fresh player applies the equalizer', () {
    expect(
      eqNeedsApply(applied: false, sessionId: 7, appliedSessionId: null),
      isTrue,
    );
  });

  test('the same session does not re-apply', () {
    expect(
      eqNeedsApply(applied: true, sessionId: 7, appliedSessionId: 7),
      isFalse,
    );
  });

  test('a new session re-applies on the session the effect was not built for',
      () {
    expect(
      eqNeedsApply(applied: true, sessionId: 8, appliedSessionId: 7),
      isTrue,
    );
  });

  test('a missing session is not a change; the stream reports it later', () {
    expect(
      eqNeedsApply(applied: true, sessionId: null, appliedSessionId: 7),
      isFalse,
    );
    expect(
      eqNeedsApply(applied: true, sessionId: null, appliedSessionId: null),
      isFalse,
    );
  });
}
