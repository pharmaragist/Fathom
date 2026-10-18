import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:just_audio/just_audio.dart';

import '../states.dart';
import '../components/glass.dart';

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FathomPlayer>().ensureEqReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final player = context.watch<FathomPlayer>();
    final settings = context.watch<FathomSettings>();
    final accent = settings.accent;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, bottom + 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Row(
              children: [
                const Text(
                  'Equalizer',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                _ResetButton(accent: accent),
              ],
            ),
          ),
          _ControlsCard(accent: accent, settings: settings),
          const SizedBox(height: 12),
          Expanded(
            child: player.eqReady
                ? _BandsCard(accent: accent)
                : _LockedCard(accent: accent),
          ),
        ],
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<FathomPlayer>().applyEqPreset('Flat'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TablerIcons.refresh, size: 14, color: accent),
            const SizedBox(width: 6),
            const Text(
              'Reset',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.accent, required this.settings});
  final Color accent;
  final FathomSettings settings;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 24,
      bgOpacity: 0.08,
      borderOpacity: 0.07,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TablerIcons.waveSine, size: 18, color: accent),
              const SizedBox(width: 10),
              const Text(
                'Enabled',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Switch.adaptive(
                value: settings.eqEnabled,
                activeTrackColor: accent,
                onChanged: (v) {
                  context.read<FathomPlayer>().setDeviceEqualizerEnabled(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 0.5,
            color: Colors.white.withValues(alpha: 0.10),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in kEqPresets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PresetChip(
                      label: preset,
                      selected: settings.eqPreset == preset,
                      accent: accent,
                      onTap: () {
                        context.read<FathomPlayer>().applyEqPreset(preset);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: -0.1,
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _BandsCard extends StatelessWidget {
  const _BandsCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final player = context.read<FathomPlayer>();
    return GlassContainer(
      radius: 24,
      bgOpacity: 0.08,
      borderOpacity: 0.07,
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 20),
      child: FutureBuilder<AndroidEqualizerParameters?>(
        future: player.equalizer.parameters,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white38,
                ),
              ),
            );
          }
          final params = snap.data;
          if (params == null) {
            return Center(
              child: Text(
                'Equalizer unavailable on this device.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            );
          }
          final bands = params.bands;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < bands.length; i++)
                Expanded(
                  child: _BandColumn(
                    band: bands[i],
                    minDb: params.minDecibels,
                    maxDb: params.maxDecibels,
                    accent: accent,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 24,
      bgOpacity: 0.08,
      borderOpacity: 0.07,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TablerIcons.waveSine,
              size: 42,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading equalizer',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The equalizer will appear once it initializes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BandColumn extends StatelessWidget {
  const _BandColumn({
    required this.band,
    required this.minDb,
    required this.maxDb,
    required this.accent,
  });

  final AndroidEqualizerBand band;
  final double minDb;
  final double maxDb;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final player = context.read<FathomPlayer>();
    return StreamBuilder<double>(
      stream: band.gainStream,
      initialData: band.gain,
      builder: (context, snap) {
        final gain = (snap.data ?? band.gain).clamp(minDb, maxDb);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            children: [
              Text(
                _formatDb(gain),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: gain.abs() < 0.05
                      ? Colors.white.withValues(alpha: 0.35)
                      : accent,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _VerticalSlider(
                  value: gain,
                  min: minDb,
                  max: maxDb,
                  accent: accent,
                  onChanged: (v) =>
                      player.setBandGain(band.centerFrequency.round(), v),
                  onChangeEnd: (v) => player.setBandGain(
                      band.centerFrequency.round(), v,
                      persist: true),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                frequencyLabel(band.centerFrequency.round()),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDb(double v) {
    final sign = v > 0.05 ? '+' : '';
    return '$sign${v.toStringAsFixed(1)}';
  }
}

class _VerticalSlider extends StatefulWidget {
  const _VerticalSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final Color accent;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_VerticalSlider> createState() => _VerticalSliderState();
}

class _VerticalSliderState extends State<_VerticalSlider> {
  bool _active = false;
  double _last = 0;

  double _valueAt(Offset local, double height) {
    if (height <= 0) return widget.min;
    final t = 1 - (local.dy / height).clamp(0.0, 1.0);
    return widget.min + t * (widget.max - widget.min);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final range = widget.max - widget.min;
        final t = range <= 0
            ? 0.0
            : ((widget.value - widget.min) / range).clamp(0.0, 1.0);
        final thumbY = (1 - t) * h;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _last = _valueAt(d.localPosition, h);
            setState(() => _active = true);
            widget.onChanged(_last);
          },
          onTapUp: (_) {
            setState(() => _active = false);
            widget.onChangeEnd(_last);
          },
          onTapCancel: () {
            if (_active) setState(() => _active = false);
          },
          onVerticalDragStart: (d) {
            _last = _valueAt(d.localPosition, h);
            setState(() => _active = true);
            widget.onChanged(_last);
          },
          onVerticalDragUpdate: (d) {
            _last = _valueAt(d.localPosition, h);
            widget.onChanged(_last);
          },
          onVerticalDragEnd: (_) {
            setState(() => _active = false);
            widget.onChangeEnd(_last);
          },
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SliderTrackPainter(
                    value: widget.value,
                    min: widget.min,
                    max: widget.max,
                    accent: widget.accent,
                    active: _active,
                  ),
                ),
              ),
              Positioned(
                top: (thumbY - 11).clamp(0, h - 22),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: _active ? 22 : 16,
                  height: _active ? 22 : 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                      if (_active)
                        BoxShadow(
                          color: widget.accent.withValues(alpha: 0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliderTrackPainter extends CustomPainter {
  _SliderTrackPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.active,
  });

  final double value;
  final double min;
  final double max;
  final Color accent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final range = max - min;
    if (range <= 0) return;

    final t = ((value - min) / range).clamp(0.0, 1.0);
    final zeroT = ((0.0 - min) / range).clamp(0.0, 1.0);
    final thumbY = (1 - t) * h;
    final zeroY = (1 - zeroT) * h;

    final trackPaint = Paint()..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 1.5, 0, 3, h),
        const Radius.circular(99),
      ),
      trackPaint,
    );

    final fillTop = thumbY < zeroY ? thumbY : zeroY;
    final fillBottom = thumbY < zeroY ? zeroY : thumbY;
    if (fillBottom - fillTop > 0.5) {
      final fillPaint = Paint()..color = accent;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 1.5, fillTop, 3, fillBottom - fillTop),
          const Radius.circular(99),
        ),
        fillPaint,
      );
    }

    final zeroPaint = Paint()
      ..color = Colors.white.withValues(alpha: active ? 0.25 : 0.15);
    canvas.drawRect(Rect.fromLTWH(0, zeroY - 0.5, w, 1), zeroPaint);
  }

  @override
  bool shouldRepaint(covariant _SliderTrackPainter old) =>
      old.value != value ||
      old.active != active ||
      old.accent != accent ||
      old.min != min ||
      old.max != max;
}
