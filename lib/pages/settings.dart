import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/constants.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/glass.dart';
import 'library.dart' show LibrarySort;

const Color _divider = Color(0xFF1C1C1C);
const Color _switchOff = Color(0xFF262626);
const Color _knobOff = Color(0xFF8C8C8C);

Color _onColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : Colors.black;

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
    final sort = LibrarySort
        .values[sortIndex.clamp(0, LibrarySort.values.length - 1)];

    final useArtAccent = settings.get<bool>(SettingKey.useArtAccent);
    final accentSubtitle = useArtAccent ? 'Auto (Artwork)' : 'Manual';

    final fontKey = settings.get<String>(SettingKey.fontKey);
    final fontFamily = fontKey == 'Oswald' ? 'Oswald' : null;

    final speedIndex = settings.get<int>(SettingKey.speedIndex);
    final gapless = settings.get<bool>(SettingKey.gapless);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
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
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(TablerIcons.x, color: Colors.white, size: 24),
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
                          color: Colors.white.withValues(alpha: 0.35),
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
    barrierColor: Colors.black.withValues(alpha: 0.6),
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
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Colors.white,
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
                  onChanged: (val) => settings.set(SettingKey.useArtAccent, val),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: _divider,
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
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.14),
                              width: (!useArt && currentAccentIndex == i)
                                  ? 2.5
                                  : 1,
                            ),
                          ),
                          child: (!useArt && currentAccentIndex == i)
                              ? Icon(
                                  TablerIcons.check,
                                  size: 22,
                                  color: _onColor(FathomColors.accentSwatches[i]),
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
        rows.add(const Divider(
          height: 1,
          thickness: 1,
          indent: 62,
          color: _divider,
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
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        GlassContainer(
          radius: 20,
          bgOpacity: 0.4,
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
  });

  final IconData icon;
  final Color accent;
  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            _IconTile(icon: icon, accent: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
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
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          if (valueWidget != null) valueWidget!,
          if (showChevron) ...[
            const SizedBox(width: 6),
            Icon(
              TablerIcons.chevronRight,
              size: 20,
              color: Colors.white.withValues(alpha: 0.3),
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
  });

  final IconData icon;
  final Color accent;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      icon: icon,
      accent: accent,
      label: label,
      onTap: () => onChanged(!value),
      trailing: _FlatSwitch(value: value, accent: accent),
    );
  }
}

class _FlatSwitch extends StatelessWidget {
  const _FlatSwitch({required this.value, required this.accent});

  final bool value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 50,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? accent : _switchOff,
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
            color: value ? _onColor(accent) : _knobOff,
          ),
        ),
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
      color: selected ? accent : Colors.white,
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
