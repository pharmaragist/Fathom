import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/constants.dart';
import '../common/library.dart';
import '../common/motion.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/color_seed_picker.dart';
import '../components/flat_switch.dart';
import '../components/glass.dart';
import '../components/sticky_header.dart';
import '../services/fonts.dart';
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

    final fontKey = settings.get<String>(SettingKey.fontKey);
    final fontFamily = fontKey == 'System' ? null : fontKey;

    final speedIndex = settings.get<int>(SettingKey.speedIndex);
    final themeIndex = settings.get<int>(SettingKey.themeIndex).clamp(0, 2);
    final gapless = settings.get<bool>(SettingKey.gapless);
    final dataSave = settings.get<bool>(SettingKey.dataSave);
    final amoled = settings.get<bool>(SettingKey.amoled);
    final powerSave =
        context.select<FathomPowerState, bool>((p) => p.isPowerSave);
    final batteryExempt =
        context.select<FathomPowerState, bool>((p) => p.isBatteryExempt);
    final lowEnd = settings.lowEndInForce(powerSave: powerSave);

    List<Widget> section(String title, List<Widget> children) => [
          SliverSectionLabel(label: title),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FlatContainer(
                radius: 20,
                filled: false,
                accent: accent,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(children: _withDividers(children)),
                ),
              ),
            ),
          ),
        ];

    return Scaffold(
      backgroundColor: FathomColors.background,
      body: DefaultTextStyle(
        style: TextStyle(fontFamily: fontFamily),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPageHeader(
              title: 'Settings',
              topInset: top,
              trailing: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(TablerIcons.x,
                    color: FathomColors.onSurface, size: 24),
              ),
            ),
            ...section('Library', [
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
            ]),
            ...section('Playback', [
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
              _NavRow(
                icon: TablerIcons.batteryCharging,
                accent: accent,
                label: 'Background playback',
                value: batteryExempt ? 'Allowed' : 'Restricted',
                onTap: () {
                  context.read<FathomPowerState>().requestBatteryExemption();
                },
              ),
            ]),
            ...section('Data', [
              _SwitchRow(
                icon: TablerIcons.cloudDownload,
                accent: accent,
                label: 'Data save mode',
                value: dataSave,
                onChanged: (v) {
                  context.read<FathomSettings>().set(SettingKey.dataSave, v);
                },
              ),
            ]),
            ...section('Appearance', [
              _NavRow(
                icon: TablerIcons.palette,
                accent: accent,
                label: 'Accent color',
                value: 'Manual',
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
                icon: TablerIcons.download,
                accent: accent,
                label: 'Get fonts',
                value: '${FathomFonts.instance.installed.length} installed',
                onTap: () => showFontsSheet(context),
              ),
              _NavRow(
                icon: TablerIcons.sunMoon,
                accent: accent,
                label: 'Theme',
                value: _kThemeLabels[themeIndex],
                onTap: () => _showThemeSheet(context),
              ),
              _SwitchRow(
                icon: TablerIcons.moon,
                accent: accent,
                label: 'AMOLED black',
                value: amoled,
                onChanged: (v) {
                  context.read<FathomSettings>().set(SettingKey.amoled, v);
                },
              ),
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
            ]),
            SliverToBoxAdapter(child: SizedBox(height: bottom + 160)),
          ],
        ),
      ),
    );
  }
}

List<Widget> _withDividers(List<Widget> children) {
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
  return rows;
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
    sheetAnimationStyle: kModalMotion,
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
          final currentAccentIndex = settings.get<int>(SettingKey.accentIndex);
          final seeds = settings.accentSeeds;
          final swatches = [
            for (final seed in seeds) FathomColors.readableAccent(seed),
          ];

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < seeds.length; i++)
                  GestureDetector(
                    onTap: () => settings.set(SettingKey.accentIndex, i),
                    child: SpringValue(
                      value: currentAccentIndex == i ? 1.0 : 0.0,
                      spring: FathomMotion.press,
                      builder: (context, t) {
                        final grip = t.clamp(0.0, 1.0);
                        return Transform.scale(
                          scale: 1 + 0.06 * grip,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: swatches[i],
                              border: Border.all(
                                color: Color.lerp(
                                  FathomColors.onSurface
                                      .withValues(alpha: 0.14),
                                  FathomColors.onSurface,
                                  grip,
                                )!,
                                width: 1 + 1.5 * grip,
                              ),
                            ),
                            child: currentAccentIndex == i
                                ? Icon(
                                    TablerIcons.check,
                                    size: 22,
                                    color: FathomColors.onAccent(swatches[i]),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                GestureDetector(
                  onTap: () => _addAccentSeed(context, settings),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: FathomColors.hairline),
                    ),
                    child: Icon(
                      TablerIcons.plus,
                      size: 22,
                      color: FathomColors.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _addAccentSeed(
  BuildContext context,
  FathomSettings settings,
) {
  return showColorSeedPicker(
    context,
    initial: settings.accent,
    onAdd: (color) {
      if (!settings.addAccentSeed(color)) return false;
      settings.set(SettingKey.accentIndex, settings.accentSeeds.length - 1);
      return true;
    },
  );
}

void _showTypographySheet(BuildContext context) {
  final settings = context.read<FathomSettings>();
  final accent = settings.accent;
  final currentFontKey = settings.get<String>(SettingKey.fontKey);
  final fonts = [
    ...kFontOptions,
    for (final family in FathomFonts.instance.installed)
      if (!kFontOptions.contains(family)) family,
  ];

  _showSheet(
    context,
    title: 'Typography',
    builder: (ctx) => Column(
      children: [
        for (final font in fonts)
          _OptionRow(
            label: font,
            labelStyle: font == 'System' ? null : TextStyle(fontFamily: font),
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

/// Opens the Google Fonts browser.
///
/// A font is downloaded only when it is picked, and picking one installs it and
/// selects it in the same step. The catalogue is fetched on demand, so the sheet
/// needs a connection; a failure keeps it open with a retry.
Future<void> showFontsSheet(BuildContext context) async {
  final settings = context.read<FathomSettings>();
  final accent = settings.accent;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: FathomColors.scrim,
    isScrollControlled: true,
    sheetAnimationStyle: kModalMotion,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.62,
            child: GlassContainer(
              radius: 28,
              accent: accent,
              shadow: true,
              child: _FontsSheet(
                accent: accent,
                current: settings.get<String>(SettingKey.fontKey),
                onPicked: (family) {
                  settings.set(SettingKey.fontKey, family);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FontsSheet extends StatefulWidget {
  const _FontsSheet({
    required this.accent,
    required this.current,
    required this.onPicked,
  });

  final Color accent;
  final String current;
  final ValueChanged<String> onPicked;

  @override
  State<_FontsSheet> createState() => _FontsSheetState();
}

class _FontsSheetState extends State<_FontsSheet> {
  static const int _maxResults = 80;

  final TextEditingController _query = TextEditingController();
  late Future<List<FathomFontFamily>> _catalogue;
  String? _installing;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _catalogue = FathomFonts.instance.catalogue();
    _query.addListener(() => setState(() => _failure = null));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _failure = null;
      _catalogue = FathomFonts.instance.catalogue();
    });
  }

  List<FathomFontFamily> _matches(List<FathomFontFamily> all) {
    final terms = _query.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    if (terms.isEmpty) return all.take(_maxResults).toList();

    final hits = <FathomFontFamily>[];
    for (final entry in all) {
      final name = entry.family.toLowerCase();
      if (terms.every(name.contains)) {
        hits.add(entry);
        if (hits.length == _maxResults) break;
      }
    }
    return hits;
  }

  Future<void> _pick(FathomFontFamily family) async {
    if (_installing != null) return;
    if (FathomFonts.instance.installed.contains(family.family)) {
      widget.onPicked(family.family);
      return;
    }

    setState(() {
      _installing = family.family;
      _failure = null;
    });

    try {
      await FathomFonts.instance.install(family.family);
      if (!mounted) return;
      widget.onPicked(family.family);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = null;
        _failure = 'Could not download ${family.family}. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Google Fonts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: FathomColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Download a family and use it across the app.',
            style: TextStyle(
              fontSize: 12.5,
              color: FathomColors.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            cursorColor: widget.accent,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FathomColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Search a font family',
              prefixIcon: Icon(
                TablerIcons.search,
                size: 18,
                color: FathomColors.onSurface.withValues(alpha: 0.4),
              ),
              hintStyle: TextStyle(
                fontSize: 15,
                color: FathomColors.onSurface.withValues(alpha: 0.35),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              filled: true,
              fillColor: FathomColors.fillFaint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 10),
            Text(
              _failure!,
              style: TextStyle(fontSize: 12, color: FathomColors.warning),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<FathomFontFamily>>(
              future: _catalogue,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FathomColors.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                  );
                }

                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Google Fonts is unavailable right now.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color:
                                FathomColors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: _retry,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: widget.accent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: FathomColors.onAccent(widget.accent),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final hits = _matches(snap.data!);
                if (hits.isEmpty) {
                  return Center(
                    child: Text(
                      'No family matches that search.',
                      style: TextStyle(
                        fontSize: 13,
                        color: FathomColors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: hits.length,
                  itemBuilder: (context, i) {
                    final family = hits[i];
                    final installed =
                        FathomFonts.instance.installed.contains(family.family);
                    final busy = _installing == family.family;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pick(family),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    family.family,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                      color: FathomColors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    family.category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: FathomColors.onSurface
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (busy)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: widget.accent,
                                ),
                              )
                            else if (family.family == widget.current ||
                                installed)
                              Icon(
                                TablerIcons.check,
                                size: 18,
                                color: widget.accent,
                              )
                            else
                              Icon(
                                TablerIcons.download,
                                size: 18,
                                color: FathomColors.onSurface
                                    .withValues(alpha: 0.35),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
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
  final bool enabled;
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
  final bool enabled;
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
      trailing: FlatSwitch(
        value: value,
        accent: accent,
        onChanged: null,
        enabled: enabled,
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
