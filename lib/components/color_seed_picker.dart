import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/colors.dart';
import '../common/motion.dart';
import '../common/settings.dart';
import 'flat_slider.dart';

/// Shows the dialog that builds a custom accent seed from HSL sliders or a
/// hex value, then hands the resulting color to [onAdd].
///
/// [onAdd] is the caller's verdict, not a formality: returning false keeps
/// this dialog open with its own message, which is how a color the settings
/// store already holds never closes the picker or changes anything. The
/// dialog itself writes no preference; the caller owns both storing the seed
/// and selecting it.
Future<void> showColorSeedPicker(
  BuildContext context, {
  required Color initial,
  required bool Function(Color color) onAdd,
}) {
  final accent = context.read<FathomSettings>().accent;
  return showDialog<void>(
    context: context,
    barrierColor: FathomColors.scrim,
    animationStyle: kModalMotion,
    builder: (ctx) => _SeedPickerDialog(
      initial: initial,
      accent: accent,
      onAdd: onAdd,
    ),
  );
}

class _SeedPickerDialog extends StatefulWidget {
  const _SeedPickerDialog({
    required this.initial,
    required this.accent,
    required this.onAdd,
  });

  final Color initial;
  final Color accent;
  final bool Function(Color color) onAdd;

  @override
  State<_SeedPickerDialog> createState() => _SeedPickerDialogState();
}

class _SeedPickerDialogState extends State<_SeedPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;
  late final TextEditingController _hex;

  /// Guard for slider-to-field writes: assigning [TextEditingController.text]
  /// fires the field's own listener, which would otherwise parse the value it
  /// was just given and write the sliders back a second time.
  bool _syncingHex = false;

  /// True after the caller refused the color, so the dialog can say why
  /// without closing.
  bool _duplicate = false;

  @override
  void initState() {
    super.initState();
    final hsl = _hslOf(widget.initial);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
    _hex = TextEditingController(text: _hexOf(_color))
      ..addListener(_onHexChanged);
  }

  @override
  void dispose() {
    _hex
      ..removeListener(_onHexChanged)
      ..dispose();
    super.dispose();
  }

  Color get _color => _colorOfHsl(_hue, _saturation, _lightness);

  /// The color the field currently spells, or null when it is not a valid
  /// `#RRGGBB` / `RRGGBB` value. An invalid field blocks Add, so the stored
  /// seed can never be the slider color while the field claims another.
  Color? get _typedColor => _parseHex(_hex.text);

  bool get _canAdd => _typedColor != null;

  void _onHexChanged() {
    if (_syncingHex) return;
    final color = _parseHex(_hex.text);
    setState(() {
      _duplicate = false;
      if (color == null) return;
      // Typing the same color back must not move a hue slider sitting at 360
      // to 0, which would look like the field fought the sliders.
      if (color.toARGB32() == _color.toARGB32()) return;
      final hsl = _hslOf(color);
      _hue = hsl.hue;
      _saturation = hsl.saturation;
      _lightness = hsl.lightness;
    });
  }

  void _update({double? hue, double? saturation, double? lightness}) {
    setState(() {
      if (hue != null) _hue = hue;
      if (saturation != null) _saturation = saturation;
      if (lightness != null) _lightness = lightness;
      _duplicate = false;
    });
    _syncHexField();
  }

  void _syncHexField() {
    final text = _hexOf(_color);
    if (_hex.text == text) return;
    _syncingHex = true;
    _hex.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncingHex = false;
  }

  void _submit() {
    final color = _typedColor;
    if (color == null) return;
    if (widget.onAdd(color)) {
      Navigator.of(context).pop();
    } else {
      setState(() => _duplicate = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final invalid = !_canAdd;

    return Dialog(
      backgroundColor: FathomColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Custom accent',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: FathomColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A seed color. Fathom builds its palette from it.',
              style: TextStyle(
                fontSize: 12.5,
                color: FathomColors.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: FathomColors.hairline),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _hexOf(color),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: FathomColors.onSurface.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _HslRow(
              label: 'Hue',
              readout: '${_hue.round()}\u00B0',
              value: _hue / 360,
              color: color,
              onChanged: (value) => _update(hue: value * 360),
            ),
            _HslRow(
              label: 'Saturation',
              readout: '${_saturation.round()}%',
              value: _saturation / 100,
              color: color,
              onChanged: (value) => _update(saturation: value * 100),
            ),
            _HslRow(
              label: 'Lightness',
              readout: '${_lightness.round()}%',
              value: _lightness / 100,
              color: color,
              onChanged: (value) => _update(lightness: value * 100),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _hex,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: widget.accent,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: FathomColors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                hintText: '#RRGGBB',
                hintStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: FathomColors.onSurface.withValues(alpha: 0.3),
                ),
                filled: true,
                fillColor: FathomColors.fillFaint,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: widget.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            if (invalid || _duplicate) ...[
              const SizedBox(height: 8),
              Text(
                invalid
                    ? 'Enter six hex digits, for example #DC8666.'
                    : 'That seed is already in the accent list.',
                style: TextStyle(
                  fontSize: 12,
                  color: FathomColors.warning,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _PickerButton(
                  label: 'Cancel',
                  color: FathomColors.onSurface.withValues(alpha: 0.75),
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _PickerButton(
                  label: 'Add',
                  filled: true,
                  color: widget.accent,
                  enabled: _canAdd,
                  onTap: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled HSL control. The track takes the preview color so the slider
/// itself shows what the value is doing.
class _HslRow extends StatelessWidget {
  const _HslRow({
    required this.label,
    required this.readout,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final String readout;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface.withValues(alpha: 0.65),
              ),
            ),
            Text(
              readout,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface.withValues(alpha: 0.5),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        FlatSlider(
          value: value,
          color: color,
          onChanged: onChanged,
          onChangeEnd: (_) {},
        ),
      ],
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? FathomColors.onAccent(color) : color;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color:
                filled ? color.withValues(alpha: 0.9) : FathomColors.fillFaint,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// HSL to an opaque RGB color, by hand.
///
/// `material_color_utilities` works in HCT, which is not what these sliders
/// speak, and a single round of conversion does not justify a package.
Color _colorOfHsl(double hue, double saturation, double lightness) {
  final h = ((hue % 360) + 360) % 360;
  final s = (saturation / 100).clamp(0.0, 1.0);
  final l = (lightness / 100).clamp(0.0, 1.0);

  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;

  final (r, g, b) = switch ((h / 60).floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };

  int channel(double value) => ((value + m) * 255).round().clamp(0, 255);
  return Color.fromARGB(255, channel(r), channel(g), channel(b));
}

/// The HSL triple behind [color], with saturation and lightness in 0..100.
({double hue, double saturation, double lightness}) _hslOf(Color color) {
  final argb = color.toARGB32();
  final r = ((argb >> 16) & 0xFF) / 255;
  final g = ((argb >> 8) & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;

  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final lightness = (max + min) / 2;
  final delta = max - min;
  if (delta == 0) {
    return (hue: 0, saturation: 0, lightness: lightness * 100);
  }

  final saturation = delta / (1 - (2 * lightness - 1).abs());
  final double hue;
  if (max == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (max == g) {
    hue = 60 * ((b - r) / delta + 2);
  } else {
    hue = 60 * ((r - g) / delta + 4);
  }
  return (
    hue: hue < 0 ? hue + 360 : hue,
    saturation: (saturation * 100).clamp(0.0, 100.0),
    lightness: lightness * 100,
  );
}

String _hexOf(Color color) => '#'
    '${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `#RRGGBB` or `RRGGBB`, or null for anything else. The field is the
/// only place a malformed value can come from, so this is also its validator.
Color? _parseHex(String text) {
  var value = text.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length != 6) return null;
  final rgb = int.tryParse(value, radix: 16);
  if (rgb == null) return null;
  return Color(0xFF000000 | rgb);
}
