import 'package:flutter/material.dart';

import '../common/colors.dart';
import '../common/motion.dart';

/// The app's own on/off switch: a flat track with a sliding knob, tinted by
/// the accent. Used instead of [Switch] so toggles look the same on every
/// page and never depend on Material defaults.
class FlatSwitch extends StatelessWidget {
  const FlatSwitch({
    super.key,
    required this.value,
    required this.accent,
    this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final Color accent;

  /// Fires when a tap belongs to the switch itself.
  ///
  /// Null removes the switch's tap recognizer and leaves the tap to whatever
  /// target surrounds it — a settings row is the one tap target for its
  /// title, hint and switch, so the switch inside it is a display of [value]
  /// only and the toggle fires exactly once. Null therefore does not mean
  /// "disabled" on its own; that state is [enabled]'s to show.
  final ValueChanged<bool>? onChanged;

  /// False shows the disabled state — dimmed, and inert even when
  /// [onChanged] is set. True is fully rendered, with the gesture wired from
  /// [onChanged].
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        // The knob, its tint and the track fill are one state change, so they
        // ride one spring. The thumb keeps travelling past its slot for a
        // fraction of a frame, which is what makes the toggle feel thrown
        // rather than slid.
        child: SpringValue(
          value: value ? 1.0 : 0.0,
          spring: FathomMotion.press,
          builder: (context, t) {
            return Container(
              width: 50,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Color.lerp(
                  FathomColors.fillStrong,
                  accent,
                  t.clamp(0.0, 1.0),
                ),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Align(
                alignment: Alignment(-1 + 2 * t, 0),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      FathomColors.onSurfaceDim,
                      FathomColors.onAccent(accent),
                      t.clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
