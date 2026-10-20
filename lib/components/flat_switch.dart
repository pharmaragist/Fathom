import 'package:flutter/material.dart';

import '../common/colors.dart';

/// The app's own on/off switch: a flat track with a sliding knob, tinted by
/// the accent. Used instead of [Switch] so toggles look the same on every
/// page and never depend on Material defaults.
class FlatSwitch extends StatelessWidget {
  const FlatSwitch({
    super.key,
    required this.value,
    required this.accent,
    this.onChanged,
  });

  final bool value;
  final Color accent;

  /// Null renders the switch in its disabled, non-interactive state.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Opacity(
        opacity: onChanged == null ? 0.4 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? accent : FathomColors.fillStrong,
            borderRadius: BorderRadius.circular(99),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value
                    ? FathomColors.onAccent(accent)
                    : FathomColors.onSurfaceDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
