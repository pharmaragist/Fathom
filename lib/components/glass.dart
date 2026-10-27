import 'dart:ui';
import 'package:flutter/material.dart';

import '../common/colors.dart';

/// The visual recipe of a *flat* card: the look every surface in this file
/// renders when nothing is frosting the edge behind it.
///
/// A flat card sits directly on whatever is behind it, with no blurred sample
/// to soften the boundary, so its fill has to carry the separation on its own.
/// The recipe is an accent tint laid over the background at partial opacity,
/// which reads as a solid-but-translucent panel rather than as fog. The accent
/// stays low (0.18) so the panel colors its surroundings instead of competing
/// with the labels on top of it, and the background underneath keeps a floor of
/// opacity so a busy page backdrop cannot show through as texture. When there
/// is no accent there is nothing to tint with, so the card falls back to that
/// same translucent background alone: still a visibly raised panel, just
/// neutral.
///
/// The light theme needs a denser fill for the same reason the blur path raises
/// opacity there: a translucent surface over a light background has almost no
/// luminance to separate with, so at the dark theme's opacity the card would
/// wash out into the page. The blur path solves that by mixing toward the
/// background color; without a blur there is no such mixing, so the flat path
/// answers with a higher alpha instead.
///
/// This is the one place the recipe lives. Both [GlassContainer]'s flat branch
/// and [FlatContainer] call it, so the two surfaces cannot drift apart: a
/// change to the fill here reaches both, and there is no second copy of these
/// numbers to keep in step.
BoxDecoration _flatDecoration({
  required double radius,
  required Color? accent,
  required double borderOpacity,
  required bool shadow,
  bool filled = true,
}) {
  final isLight = FathomColors.brightness == Brightness.light;

  // An outline-only card has no fill to separate it from the page, so its 1px
  // edge is the whole surface: it uses the shared hairline token, the same
  // color the section rules inside the card are drawn with. A tinted or
  // translucent border (the filled recipe below) would disappear against a
  // page whose rows already carry their own borders.
  if (!filled) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: FathomColors.hairline, width: 1),
    );
  }

  final Color flatFill;
  if (accent != null) {
    final panelAlpha = isLight ? 0.86 : 0.72;
    final tintAlpha = isLight ? 0.14 : 0.18;
    flatFill = Color.alphaBlend(
      accent.withValues(alpha: tintAlpha),
      FathomColors.background.withValues(alpha: panelAlpha),
    );
  } else {
    flatFill = FathomColors.background.withValues(alpha: isLight ? 0.86 : 0.72);
  }

  // Blend accent with the foreground for a crisp edge highlight that still
  // belongs to the card's own color rather than to the page. The light theme
  // needs a stronger outline for the same reason it needs a denser fill.
  final baseOutline = _outlineColor(accent);
  final effectiveBorderOpacity =
      _effectiveBorderOpacity(isLight, borderOpacity);

  return BoxDecoration(
    color: flatFill,
    borderRadius: BorderRadius.circular(radius),
    // One pixel of outline is what defines the card once nothing is frosting
    // the edge behind it.
    border: Border.all(
      color: baseOutline.withValues(alpha: effectiveBorderOpacity),
      width: 1,
    ),
    boxShadow: shadow
        ? [
            BoxShadow(
              color: FathomColors.shadow.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: -2,
            ),
          ]
        : null,
  );
}

/// The card's edge color: the accent blended with the foreground for a crisp
/// highlight, or the plain foreground when there is no accent to blend.
/// Shared with [FlatContainer] through [_flatDecoration]; kept beside it so the
/// border logic has one home.
Color _outlineColor(Color? accent) => accent != null
    ? Color.alphaBlend(accent.withValues(alpha: 0.35), FathomColors.onSurface)
    : FathomColors.onSurface;

/// The border opacity a caller asked for, raised for the light theme, where a
/// faint outline over a pale page is nearly invisible.
double _effectiveBorderOpacity(bool isLight, double borderOpacity) =>
    isLight ? (borderOpacity * 1.8).clamp(0.0, 1.0) : borderOpacity;

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 16,
    this.bgOpacity = 0.65,
    this.borderOpacity = 0.07,
    this.accent,
    this.padding,
    this.shadow = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final double bgOpacity;
  final double borderOpacity;
  final Color? accent;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  /// Whether this surface is allowed to pay for a [BackdropFilter].
  ///
  /// Written exactly once, by `FathomApp` from `SettingKey.lowEnd`, and read
  /// here during build: when false the card renders as a flat translucent
  /// rectangle with no blur, which is the whole point of the low-end setting.
  ///
  /// It is deliberately a plain static and not a notifier or a constructor
  /// parameter. A notifier would rebuild every [GlassContainer] on a write, and
  /// a parameter would have to be threaded through every call site. The cost of
  /// that choice is that changing the value does not repaint by itself, so the
  /// writer must rebuild the subtree that owns these cards; `FathomApp` does,
  /// because it reads the setting on every build.
  static bool blurEnabled = true;

  @override
  Widget build(BuildContext context) {
    final isLight = FathomColors.brightness == Brightness.light;

    Widget content =
        padding != null ? Padding(padding: padding!, child: child) : child;

    // The flat state's decoration, borrowed from the one shared recipe so the
    // low-end look and [FlatContainer] can never disagree about it.
    final flatDecoration = _flatDecoration(
      radius: radius,
      accent: accent,
      borderOpacity: borderOpacity,
      shadow: shadow,
    );

    final Widget decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: blurEnabled
          ? BoxDecoration(
              color: FathomColors.background.withValues(
                alpha: isLight
                    ? (0.72 + bgOpacity * 0.28).clamp(0.0, 1.0)
                    : bgOpacity,
              ),
              borderRadius: BorderRadius.circular(radius),
              // One pixel of outline is what defines the card once nothing is
              // frosting the edge behind it. It stays on both paths so a toggle
              // animates the fill rather than snapping the shape away.
              border: Border.all(
                color: _outlineColor(accent).withValues(
                  alpha: _effectiveBorderOpacity(isLight, borderOpacity),
                ),
                width: 1,
              ),
              boxShadow: shadow
                  ? [
                      BoxShadow(
                        color: FathomColors.shadow.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            )
          : flatDecoration,
      child: content,
    );

    // The two states are structurally different subtrees, not one tree with a
    // zero sigma. A [BackdropFilter] in the tree costs a saveLayer even at
    // sigma 0, so the flat branch must not contain one at all.
    if (!blurEnabled) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: decorated,
      ),
    );
  }
}

/// A flat counterpart to [GlassContainer] for cards that sit *behind* opaque
/// content inside a page rather than floating over live content.
///
/// It renders the same surface [GlassContainer] renders when
/// [GlassContainer.blurEnabled] is off — the shared recipe in
/// [_flatDecoration] — but it is a separate widget on purpose, not
/// [GlassContainer] plus a flag: there is no [BackdropFilter] anywhere in its
/// subtree, so it can never pay for a `saveLayer`, whatever the low-end setting
/// says. A card whose content is opaque (a list of rows, a row of labels and
/// chips, a status panel) covers the pixels behind it entirely, so blurring
/// them would be work with nothing to show for it.
///
/// Use [GlassContainer] when the card floats over content the user can still
/// see around and through it — sheets, the mini player, an inline label over a
/// list — where the blur is what makes the card read as a separate layer. Use this one when the card is just a panel in a page's own
/// layout.
class FlatContainer extends StatelessWidget {
  const FlatContainer({
    super.key,
    required this.child,
    this.radius = 22,
    this.accent,
    this.padding,
    this.shadow = false,
    this.borderOpacity = 0.07,
    this.filled = true,
  });

  final Widget child;
  final double radius;
  final Color? accent;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  /// Whether the card paints the translucent fill recipe behind its content.
  ///
  /// True is the default panel. False renders the card as an outline only: the
  /// shared hairline border, no fill and no shadow, with the page showing
  /// through the body. That is the right look for a page whose cards are
  /// really stacks of rows with their own separators (Settings sections, the
  /// equalizer cards) — a filled body there reads as a second, competing
  /// surface behind content that already defines itself with rules.
  ///
  /// [borderOpacity] only applies to the filled form; the outline-only form
  /// always uses [FathomColors.hairline] so it matches the dividers inside it.
  final bool filled;

  /// The alpha of the card's 1px outline. It is the same knob
  /// [GlassContainer.borderOpacity] is, and it means the same thing here, so
  /// the name is kept.
  ///
  /// There are deliberately no `blur` or `bgOpacity` parameters. A blur has no
  /// meaning on a surface that must never sample what is behind it, and the
  /// flat fill is a fixed recipe ([_flatDecoration]) rather than a caller-tuned
  /// opacity: the fill and the accent tint have to move together to stay a
  /// legible panel, so exposing one of them alone would only let a caller
  /// break it. [GlassContainer.bgOpacity] had no effect on the flat path
  /// either, which is why the callers converted here were passing values as
  /// disparate as 0.08 and 0.4 with no visible difference.
  final double borderOpacity;

  @override
  Widget build(BuildContext context) {
    final content =
        padding != null ? Padding(padding: padding!, child: child) : child;

    // AnimatedContainer, like [GlassContainer], so an accent change animates
    // the fill instead of snapping it.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: _flatDecoration(
          radius: radius,
          accent: accent,
          borderOpacity: borderOpacity,
          shadow: shadow,
          filled: filled,
        ),
        child: content,
      ),
    );
  }
}
