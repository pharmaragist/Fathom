import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/constants.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/flat_switch.dart';
import '../components/glass.dart';
import '../services/power.dart';
import 'library.dart' show LibrarySort;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<FathomSettings>();
    final status =
        context.select<FathomLibrary, FathomLibraryStatus>((l) => l.status);
    final trackCount =
        context.select<FathomLibrary, int>((l) => l.tracks.length);
    final top = MediaQuery.viewPaddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final accent = settings.accent;

    final sortIndex = settings.get<int>(SettingKey.sortIndex);
    final sort =
        LibrarySort.values[sortIndex.clamp(0, LibrarySort.values.length - 1)];

    final useArtAccent = settings.get<bool>(SettingKey.useArtAccent);
    final accentSubtitle = useArtAccent ? 'Auto (Artwork)' : 'Manual';

    final fontKey = settings.get<String>(SettingKey.fontKey);
    final fontFamily = fontKey == 'Oswald' ? 'Oswald' : null;

    final speedIndex = settings.get<int>(SettingKey.speedIndex);
    final themeIndex = settings.get<int>(SettingKey.themeIndex).clamp(0, 2);
    final gapless = settings.get<bool>(SettingKey.gapless);
    final dataSave = settings.get<bool>(SettingKey.dataSave);
    // The row shows the effective state, not the stored preference: while the
    // device saves power, low-end is on and locked, and `settings.lowEndInForce`
    // is the same answer the app's glass sync uses.
    final powerSave =
        context.select<FathomPowerState, bool>((p) => p.isPowerSave);
    final lowEnd = settings.lowEndInForce(powerSave: powerSave);

    return Scaffold(
      backgroundColor: FathomColors.background,
      body: DefaultTextStyle(
        style: TextStyle(fontFamily: fontFamily),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, bottom + 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: FathomColors.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(TablerIcons.x,
                        color: FathomColors.onSurface, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Section(
                title: 'Library',
                accent: accent,
                children: [
                  _NavRow(
                    icon: TablerIcons.arrowsSort,
                    accent: accent,
                    label: 'Default sort',
                    value: sort.label,
                    onTap: () => _showSortSheet(context),
                  ),
                  _NavRow(
                    icon: TablerIcons.refresh,
                    accent: accent,
                    label: 'Rescan library',
                    value: status == FathomLibraryStatus.loading
                        ? 'Scanning'
                        : '$trackCount tracks',
                    showChevron: false,
                    onTap: () {
                      if (status == FathomLibraryStatus.loading) return;
                      context.read<FathomLibrary>().load(grantIfMissing: false);
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Playback',
                accent: accent,
                children: [
                  _NavRow(
                    icon: TablerIcons.gauge,
                    accent: accent,
                    label: 'Playback speed',
                    value: kSpeedLabels[speedIndex],
                    onTap: () => _showSpeedSheet(context),
                  ),
                  _SwitchRow(
                    icon: TablerIcons.chevronsRight,
                    accent: accent,
                    label: 'Gapless playback',
                    value: gapless,
                    onChanged: (v) {
                      context.read<FathomSettings>().set(SettingKey.gapless, v);
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Data',
                accent: accent,
                children: [
                  _SwitchRow(
                    icon: TablerIcons.cloudDownload,
                    accent: accent,
                    label: 'Data save mode',
                    value: dataSave,
                    onChanged: (v) {
                      context
                          .read<FathomSettings>()
                          .set(SettingKey.dataSave, v);
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Appearance',
                accent: accent,
                children: [
                  _NavRow(
                    icon: TablerIcons.palette,
                    accent: accent,
                    label: 'Accent color',
                    value: accentSubtitle,
                    valueWidget: Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: FathomColors.onSurface.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    ),
                    onTap: () => _showAccentSheet(context),
                  ),
                  _NavRow(
                    icon: TablerIcons.typography,
                    accent: accent,
                    label: 'Typography',
                    value: fontKey,
                    onTap: () => _showTypographySheet(context),
                  ),
                  _NavRow(
                    icon: TablerIcons.sunMoon,
                    accent: accent,
                    label: 'Theme',
                    value: _kThemeLabels[themeIndex],
                    onTap: () => _showThemeSheet(context),
                  ),
                  // Swapping the frosted glass surfaces for flat translucent
                  // cards is a look-and-feel tradeoff, so it lives with the
                  // other appearance choices rather than in the Data section.
                  // Battery saver overrides it: the device is already working
                  // to save power, so the blur goes and the row reads as ON and
                  // locked, with the reason underneath. The stored preference
                  // is untouched and comes back the moment power save ends.
                  _SwitchRow(
                    icon: TablerIcons.feather,
                    accent: accent,
                    label: 'Low-end mode',
                    value: lowEnd,
                    enabled: !powerSave,
                    hint: powerSave ? 'On: battery saver' : null,
                    onChanged: (v) {
                      context.read<FathomSettings>().set(SettingKey.lowEnd, v);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showSheet(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext sheetContext) builder,
}) {
  final accent = context.read<FathomSettings>().accent;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: FathomColors.scrim,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: GlassContainer(
          radius: 28,
          bgOpacity: 0.65,
          borderOpacity: 0.07,
          accent: accent,
          shadow: true,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: FathomColors.onSurface,
                      ),
                    ),
                  ),
                  Flexible(child: SingleChildScrollView(child: builder(ctx))),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _showSortSheet(BuildContext context) {
  final settings = context.read<FathomSettings>();
  final accent = settings.accent;
  final currentSortIndex = settings.get<int>(SettingKey.sortIndex);

  _showSheet(
    context,
    title: 'Default sort',
    builder: (ctx) => Column(
      children: [
        for (final option in LibrarySort.values)
          _OptionRow(
            label: option.label,
            selected: currentSortIndex == option.index,
            accent: accent,
            onTap: () {
              settings.set(SettingKey.sortIndex, option.index);
              Navigator.of(ctx).maybePop();
            },
          ),
      ],
    ),
  );
}

void _showSpeedSheet(BuildContext context) {
  final settings = context.read<FathomSettings>();
  final player = context.read<FathomPlayer>();
  final accent = settings.accent;
  final currentSpeedIndex = settings.get<int>(SettingKey.speedIndex);

  _showSheet(
    context,
    title: 'Playback speed',
    builder: (ctx) => Column(
      children: [
        for (var i = 0; i < kSpeedLabels.length; i++)
          _OptionRow(
            label: kSpeedLabels[i],
            selected: currentSpeedIndex == i,
            accent: accent,
            onTap: () {
              settings.set(SettingKey.speedIndex, i);
              player.setSpeedFactor(kSpeedFactors[i]);
              Navigator.of(ctx).maybePop();
            },
          ),
      ],
    ),
  );
}

const _kThemeLabels = <String>['Light', 'Dark', 'Auto (Device)'];

void _showThemeSheet(BuildContext context) {
  final settings = context.read<FathomSettings>();
  final accent = settings.accent;
  final currentThemeIndex =
      settings.get<int>(SettingKey.themeIndex).clamp(0, 2);

  _showSheet(
    context,
    title: 'Theme',
    builder: (ctx) => Column(
      children: [
        for (var i = 0; i < _kThemeLabels.length; i++)
          _OptionRow(
            label: _kThemeLabels[i],
            selected: currentThemeIndex == i,
            accent: accent,
            onTap: () {
              settings.set(SettingKey.themeIndex, i);
              Navigator.of(ctx).maybePop();
            },
          ),
      ],
    ),
  );
}

void _showAccentSheet(BuildContext context) {
  _showSheet(
    context,
    title: 'Accent color',
    builder: (ctx) {
      return Consumer<FathomSettings>(
        builder: (context, settings, _) {
          final accent = settings.accent;
          final useArt = settings.get<bool>(SettingKey.useArtAccent);
          final currentAccentIndex = settings.get<int>(SettingKey.accentIndex);

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwitchRow(
                  icon: TablerIcons.colorFilter,
                  accent: accent,
                  label: 'Match track artwork',
                  value: useArt,
                  onChanged: (val) =>
                      settings.set(SettingKey.useArtAccent, val),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: FathomColors.hairline,
                  ),
                ),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (var i = 0; i < FathomColors.accentSwatches.length; i++)
                      GestureDetector(
                        onTap: () {
                          settings.set(SettingKey.accentIndex, i);
                          settings.set(SettingKey.useArtAccent, false);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: FathomColors.accentSwatches[i],
                            border: Border.all(
                              color: (!useArt && currentAccentIndex == i)
                                  ? FathomColors.onSurface
                                  : FathomColors.onSurface
                                      .withValues(alpha: 0.14),
                              width: (!useArt && currentAccentIndex == i)
                                  ? 2.5
                                  : 1,
                            ),
                          ),
                          child: (!useArt && currentAccentIndex == i)
                              ? Icon(
                                  TablerIcons.check,
                                  size: 22,
                                  color: FathomColors.onAccent(
                                      FathomColors.accentSwatches[i]),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void _showTypographySheet(BuildContext context) {
  final settings = context.read<FathomSettings>();
  final accent = settings.accent;
  final currentFontKey = settings.get<String>(SettingKey.fontKey);

  _showSheet(
    context,
    title: 'Typography',
    builder: (ctx) => Column(
      children: [
        for (final font in kFontOptions)
          _OptionRow(
            label: font,
            labelStyle:
                font == 'Oswald' ? const TextStyle(fontFamily: 'Oswald') : null,
            selected: currentFontKey == font,
            accent: accent,
            onTap: () {
              settings.set(SettingKey.fontKey, font);
              Navigator.of(ctx).maybePop();
            },
          ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.accent,
  });

  final String title;
  final List<Widget> children;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: 62,
          color: FathomColors.hairline,
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 22, 0, 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: FathomColors.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        // A section is a panel in the page's own layout, sitting behind rows
        // that are all opaque, so there is nothing behind it worth sampling.
        FlatContainer(
          radius: 20,
          borderOpacity: 0.07,
          accent: accent,
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: accent),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.icon,
    required this.accent,
    required this.label,
    required this.trailing,
    required this.onTap,
    this.enabled = true,
    this.hint,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  /// False dims the row and drops its tap, for a row whose value is being
  /// decided elsewhere. Defaults to true so every existing caller is unchanged.
  final bool enabled;

  /// One short line under the label explaining a state the user did not
  /// choose, such as why a row is locked. Null renders nothing, and the row
  /// height is unchanged either way for rows that omit it.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Opacity(
              opacity: enabled ? 1 : 0.4,
              child: _IconTile(icon: icon, accent: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      // A row locked by device state can only dim; it has no
                      // disabled tone of its own to switch to.
                      color: enabled
                          ? FathomColors.onSurface
                          : FathomColors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: FathomColors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.onTap,
    this.value,
    this.valueWidget,
    this.showChevron = true,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final Widget? valueWidget;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      icon: icon,
      accent: accent,
      label: label,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value!,
              style: TextStyle(
                fontSize: 15,
                color: FathomColors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          if (valueWidget != null) valueWidget!,
          if (showChevron) ...[
            const SizedBox(width: 6),
            Icon(
              TablerIcons.chevronRight,
              size: 20,
              color: FathomColors.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hint,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// False shows the switch in its disabled state and ignores taps. The row is
  /// still rendered, because a state the user cannot change is worth showing;
  /// `hint` is where the reason goes.
  final bool enabled;

  /// Short explanation shown under the label while the row is locked.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      icon: icon,
      accent: accent,
      label: label,
      enabled: enabled,
      hint: hint,
      onTap: () => onChanged(!value),
      // A disabled `FlatSwitch` already owns the dimming and the dropped tap,
      // so `enabled` is passed straight through rather than re-styled here.
      trailing: FlatSwitch(
        value: value,
        accent: accent,
        onChanged: enabled ? (_) {} : null,
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.labelStyle,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 16,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? accent : FathomColors.onSurface,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: base.merge(labelStyle)),
            ),
            if (selected) Icon(TablerIcons.check, size: 20, color: accent),
          ],
        ),
      ),
    );
  }
}
