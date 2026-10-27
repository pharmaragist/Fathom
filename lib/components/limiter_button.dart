import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../services/equalizer.dart';

/// The soft limiter's switch, worn as an icon in the Equalizer header.
///
/// Android's `DynamicsProcessing` exposes no gain-reduction metering, so the
/// ring is a prediction rather than a measurement: it pulses when the current
/// preamp plus the largest band boost can reach the limiter ceiling while
/// audio is playing. The tooltip says what the stage is for, so an idle ring is
/// never read as a level meter.
///
/// The pulse is a post-frame controller rather than a build-time repeat: a
/// header rebuild must not start a ticker while its ancestor is still building,
/// and nothing should tick while the ring is idle. The controller therefore has
/// exactly the lifetime of the hot state.
class LimiterButton extends StatefulWidget {
  const LimiterButton({super.key});

  @override
  State<LimiterButton> createState() => _LimiterButtonState();
}

class _LimiterButtonState extends State<LimiterButton>
    with SingleTickerProviderStateMixin {
  /// A visible dip, never a full blink-off.
  static const double _pulseFloor = 0.32;

  late final AnimationController _pulse;

  bool _pulsing = false;

  /// This frame's pulse decision, refreshed by [build].
  bool _hot = false;

  /// Guards against scheduling more than one post-frame sync per frame.
  bool _syncPending = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 860),
      lowerBound: _pulseFloor,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (_syncPending) return;
    _syncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPending = false;
      if (!mounted || _hot == _pulsing) return;

      _pulsing = _hot;
      if (_hot) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse
          ..stop()
          ..value = 1.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<FathomSettings>();
    final player = context.watch<FathomPlayer>();
    final limiterOn = settings.get<bool>(SettingKey.limiter);
    final accent = settings.accent;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);

    return ValueListenableBuilder<double>(
      valueListenable: player.maxEqBoostDecibels,
      builder: (context, boost, _) {
        // Worst case the stage can be asked to catch: input gain plus the
        // biggest band boost. A cut-only curve predicts zero. The stage is
        // only called hot when the curve actually adds gain: a flat curve at
        // unity would otherwise sit above a -1 dBFS ceiling on paper and pulse
        // for every track, which says nothing.
        final worstPeak = settings.eqPreamp + boost;
        final pushing = boost > 0.05 || settings.eqPreamp > 0.05;
        final reached = limiterOn &&
            player.isPlaying &&
            pushing &&
            worstPeak > FathomNativeEqualizer.limiterThresholdDecibels;

        _hot = reached && !animationsDisabled;
        _syncPulse();

        final idleBorder = limiterOn
            ? accent.withValues(alpha: 0.42)
            : FathomColors.onSurface.withValues(alpha: 0.18);
        final iconColor =
            limiterOn ? accent : FathomColors.onSurface.withValues(alpha: 0.42);

        return Tooltip(
          message: 'Soft peak limiter at -1 dBFS. Catches peaks from preamp '
              'and EQ boosts before they clip; it does not normalize loudness. '
              'The ring pulses when the curve can reach the ceiling.',
          child: Semantics(
            button: true,
            toggled: limiterOn,
            label: limiterOn ? 'Limiter on' : 'Limiter off',
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final pulse = _hot ? _pulse.value : 1.0;
                final border = reached
                    ? Color.lerp(idleBorder, accent, pulse)!
                    : idleBorder;

                return SizedBox(
                  width: 38,
                  height: 38,
                  child: Material(
                    // The ring is the whole control. No fill and no bloom:
                    // a glow reads as a light source behind the header, while
                    // this is only a boundary saying the limiter is armed.
                    color: Colors.transparent,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: border,
                        width: reached ? 1.5 : 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => player.setLimiter(!limiterOn),
                      child: Center(
                        child: Icon(
                          TablerIcons.shieldCheck,
                          size: 18,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
