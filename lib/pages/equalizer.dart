import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/constants.dart';
import '../common/motion.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../components/flat_slider.dart';
import '../components/flat_switch.dart';
import '../components/glass.dart';
import '../services/autoeq.dart';
import '../services/equalizer.dart';

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
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final eqReady = context.select<FathomPlayer, bool>((p) => p.eqReady);
    final native =
        context.select<FathomPlayer, bool>((p) => p.usingNativeEqualizer);
    final player = context.read<FathomPlayer>();
    final settings = context.watch<FathomSettings>();
    final accent = settings.accent;

    // The shell paints the backdrop and the header above this body, so the
    // page carries only its cards. The shell's `Expanded` gives the page a
    // tight height, exactly what the bands card needs to fill.
    //
    // The bottom inset clears the floating panel, because the page body runs
    // under it: without this the bands card's lower half sits behind the mini
    // player and the rail, where its sliders cannot be dragged and the two
    // glass surfaces end up sampling the card instead of the backdrop. The
    // value matches the list's own inset in `LibraryPage`, so both destinations
    // end their content at the same line.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ControlsCard(accent: accent, settings: settings),
          const SizedBox(height: 12),
          Expanded(
            child: eqReady
                ? _BandsCard(accent: accent, player: player, native: native)
                : _LockedCard(accent: accent),
          ),
        ],
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
    final eqEnabled = settings.get<bool>(SettingKey.eqEnabled);
    final current = settings.get<String?>(SettingKey.eqPreset);
    final builtIn = current != null ? kBuiltInEqPresets[current] : null;
    final saved = current != null ? settings.eqPresets[current] : null;
    final editing = (builtIn != null || saved != null) ? current : null;

    return FlatContainer(
      radius: 24,
      filled: false,
      accent: accent,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TablerIcons.waveSine, size: 18, color: accent),
              const SizedBox(width: 10),
              Text(
                'Enabled',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FathomColors.onSurface,
                ),
              ),
              const Spacer(),
              FlatSwitch(
                value: eqEnabled,
                accent: accent,
                onChanged: (v) {
                  context.read<FathomPlayer>().setDeviceEqualizerEnabled(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: FathomColors.hairline,
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetActionChip(
                  icon: TablerIcons.cloudDownload,
                  label: 'Get',
                  accent: accent,
                  onTap: () => showAutoEqSheet(context, accent: accent),
                ),
                const SizedBox(width: 8),
                _PresetActionChip(
                  icon: editing != null
                      ? TablerIcons.pencil
                      : TablerIcons.bookmarkPlus,
                  label: editing != null ? 'Edit' : 'Save',
                  accent: accent,
                  onTap: () => showEqPresetSheet(
                    context,
                    accent: accent,
                    editing: editing,
                  ),
                ),
                for (final name in kBuiltInEqPresets.keys) ...[
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: name,
                    selected: current == name,
                    accent: accent,
                    onTap: () {
                      context.read<FathomPlayer>().applyEqPreset(name);
                    },
                  ),
                ],
                for (final name
                    in settings.eqPresetNames(EqPresetSource.user)) ...[
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: name,
                    selected: current == name,
                    accent: accent,
                    onTap: () {
                      context.read<FathomPlayer>().applyEqPreset(name);
                    },
                  ),
                ],
                for (final name
                    in settings.eqPresetNames(EqPresetSource.autoEq)) ...[
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: name,
                    selected: current == name,
                    accent: accent,
                    onTap: () {
                      context.read<FathomPlayer>().applyEqPreset(name);
                    },
                  ),
                ],
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
      child: SpringValue(
        value: selected ? 1.0 : 0.0,
        spring: FathomMotion.press,
        builder: (context, t) {
          final grip = t.clamp(0.0, 1.0);
          return Transform.scale(
            scale: 1 + 0.02 * grip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Color.lerp(
                  FathomColors.fillFaint,
                  accent.withValues(alpha: 0.20),
                  grip,
                ),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: -0.1,
                  color: selected
                      ? FathomColors.onSurface
                      : FathomColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PresetActionChip extends StatelessWidget {
  const _PresetActionChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: FathomColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the preset sheet and applies its result to the player.
///
/// Pass [editing] with the name of the selected user preset to rename, update
/// or delete it instead of saving a new one.
Future<void> showEqPresetSheet(
  BuildContext context, {
  required Color accent,
  String? editing,
}) async {
  final player = context.read<FathomPlayer>();
  final taken = context.read<FathomSettings>().eqPresets.keys.toSet();

  final draft = await showModalBottomSheet<_PresetDraft>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    sheetAnimationStyle: kModalMotion,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GlassContainer(
            radius: 28,
            accent: accent,
            shadow: true,
            child: _PresetSheet(accent: accent, editing: editing, taken: taken),
          ),
        ),
      ),
    ),
  );

  if (draft == null) return;

  if (draft.deleted) {
    player.deleteEqPreset(draft.name);
  } else {
    player.saveEqPreset(draft.name, replacing: editing);
  }
}

/// Outcome of the preset sheet.
class _PresetDraft {
  const _PresetDraft.save(this.name) : deleted = false;
  const _PresetDraft.delete(this.name) : deleted = true;

  final String name;
  final bool deleted;
}

class _PresetSheet extends StatefulWidget {
  const _PresetSheet({
    required this.accent,
    required this.editing,
    required this.taken,
  });

  final Color accent;
  final String? editing;
  final Set<String> taken;

  @override
  State<_PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<_PresetSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.editing ?? '')
      ..addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  String get _trimmed => _name.text.trim();

  /// Validation message for the typed name, or null when it is usable.
  String? get _error {
    if (_trimmed.isEmpty) return null;
    if (kBuiltInEqPresets.containsKey(_trimmed)) {
      return 'That name is used by a built-in preset.';
    }
    if (widget.editing != null &&
        _trimmed != widget.editing &&
        widget.taken.contains(_trimmed)) {
      return 'Another preset already uses that name.';
    }
    return null;
  }

  bool get _canSave => _trimmed.isNotEmpty && _error == null;
  bool get _overwrites =>
      widget.editing == null && widget.taken.contains(_trimmed);

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_PresetDraft.save(_trimmed));
  }

  Future<void> _delete() async {
    final name = widget.editing;
    if (name == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: kModalMotion,
      builder: (ctx) => AlertDialog(
        backgroundColor: FathomColors.background,
        title: Text(
          'Delete preset?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: FathomColors.onSurface,
          ),
        ),
        content: Text(
          '"$name" will be removed. This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: FathomColors.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: FathomColors.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: FathomColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(_PresetDraft.delete(name));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'Edit preset' : 'Save preset',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: FathomColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Stores the ten bands and the preamp under a name.',
              style: TextStyle(
                fontSize: 12.5,
                color: FathomColors.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: widget.accent,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Preset name',
                hintStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: FathomColors.onSurface.withValues(alpha: 0.3),
                ),
                filled: true,
                fillColor: FathomColors.fillFaint,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: widget.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            if (_error != null || _overwrites) ...[
              const SizedBox(height: 8),
              Text(
                _error ?? 'Replaces the existing "$_trimmed" preset.',
                style: TextStyle(
                  fontSize: 12,
                  color: _error != null
                      ? FathomColors.warning
                      : FathomColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                if (editing)
                  _SheetButton(
                    label: 'Delete',
                    icon: TablerIcons.trash,
                    color: FathomColors.error,
                    onTap: _delete,
                  ),
                const Spacer(),
                _SheetButton(
                  label: 'Cancel',
                  color: FathomColors.onSurface.withValues(alpha: 0.75),
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _SheetButton(
                  label: editing ? 'Update' : 'Save',
                  filled: true,
                  color: widget.accent,
                  enabled: _canSave,
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

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color:
                filled ? color.withValues(alpha: 0.9) : FathomColors.fillFaint,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the AutoEQ browser and stores the picked result as a preset.
///
/// The catalogue is fetched on demand, so the panel needs a connection; a
/// failed download keeps the sheet open with a retry.
Future<void> showAutoEqSheet(
  BuildContext context, {
  required Color accent,
}) async {
  final player = context.read<FathomPlayer>();

  final picked = await showModalBottomSheet<AutoEqPreset>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    sheetAnimationStyle: kModalMotion,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.55,
            child: GlassContainer(
              radius: 28,
              accent: accent,
              shadow: true,
              child: _AutoEqSheet(accent: accent),
            ),
          ),
        ),
      ),
    ),
  );

  if (picked == null) return;
  player.addEqPreset(picked.name, picked.preset);
}

class _AutoEqSheet extends StatefulWidget {
  const _AutoEqSheet({required this.accent});

  final Color accent;

  @override
  State<_AutoEqSheet> createState() => _AutoEqSheetState();
}

class _AutoEqSheetState extends State<_AutoEqSheet> {
  /// Most results a single query renders. Deeper matches need a tighter query.
  static const int _maxResults = 80;

  final TextEditingController _query = TextEditingController();
  late Future<List<AutoEqEntry>> _index;

  /// The result currently being downloaded, if any.
  AutoEqEntry? _fetching;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _index = FathomAutoEq.instance.entries();
    _query.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _query
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() => _failure = null);

  void _retry() {
    setState(() {
      _failure = null;
      _index = FathomAutoEq.instance.entries();
    });
  }

  List<AutoEqEntry> _matches(List<AutoEqEntry> all) {
    final terms = _query.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    if (terms.isEmpty) return all.take(_maxResults).toList();

    final hits = <AutoEqEntry>[];
    for (final entry in all) {
      final name = entry.name.toLowerCase();
      if (terms.every(name.contains)) {
        hits.add(entry);
        if (hits.length == _maxResults) break;
      }
    }
    return hits;
  }

  Future<void> _pick(AutoEqEntry entry) async {
    if (_fetching != null) return;

    setState(() {
      _fetching = entry;
      _failure = null;
    });

    try {
      final preset = await FathomAutoEq.instance.fetch(entry);
      if (!mounted) return;
      Navigator.of(context).pop(AutoEqPreset(name: entry.name, preset: preset));
    } on AutoEqException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = null;
        _failure = e.message;
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
            'AutoEQ',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: FathomColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Measured headphone corrections, stored as a preset.',
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
              hintText: 'Search a headphone model',
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
            child: FutureBuilder<List<AutoEqEntry>>(
              future: _index,
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
                  final error = snap.error;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error is AutoEqException
                              ? error.message
                              : 'AutoEQ is unavailable right now.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color:
                                FathomColors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _SheetButton(
                          label: 'Retry',
                          icon: TablerIcons.refresh,
                          filled: true,
                          color: widget.accent,
                          onTap: _retry,
                        ),
                      ],
                    ),
                  );
                }

                final hits = _matches(snap.data!);
                if (hits.isEmpty) {
                  return Center(
                    child: Text(
                      'No headphone matches that search.',
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
                  itemBuilder: (context, i) => _AutoEqRow(
                    entry: hits[i],
                    accent: widget.accent,
                    busy: identical(_fetching, hits[i]),
                    onTap: () => _pick(hits[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoEqRow extends StatelessWidget {
  const _AutoEqRow({
    required this.entry,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final AutoEqEntry entry;
  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
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
                    entry.origin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: FathomColors.onSurface.withValues(alpha: 0.45),
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
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            else
              Icon(
                TablerIcons.plus,
                size: 16,
                color: FathomColors.onSurface.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }
}

class _BandsCard extends StatelessWidget {
  const _BandsCard({
    required this.accent,
    required this.player,
    required this.native,
  });
  final Color accent;
  final FathomPlayer player;
  final bool native;

  @override
  Widget build(BuildContext context) {
    if (native) {
      return FlatContainer(
        radius: 24,
        filled: false,
        accent: accent,
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 20),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _PreampRow(accent: accent),
            ),
            const SizedBox(height: 14),
            Divider(
              height: 1,
              thickness: 1,
              color: FathomColors.hairline,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < kEq10Bands.length; i++)
                    Expanded(
                      child: _NativeBandColumn(
                        index: i,
                        centerFrequency: kEq10Bands[i],
                        minDb: FathomNativeEqualizer.minDecibels,
                        maxDb: FathomNativeEqualizer.maxDecibels,
                        accent: accent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return FlatContainer(
      radius: 24,
      filled: false,
      accent: accent,
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 20),
      child: FutureBuilder<AndroidEqualizerParameters?>(
        future: player.hardwareEqualizer.parameters,
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
          final params = snap.data;
          if (params == null) {
            return Center(
              child: Text(
                'Equalizer unavailable on this device.',
                style: TextStyle(
                  fontSize: 13,
                  color: FathomColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            );
          }
          final bands = params.bands;
          if (bands.isEmpty) {
            return Center(
              child: Text(
                'Equalizer unavailable on this device.',
                style: TextStyle(
                  fontSize: 13,
                  color: FathomColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            );
          }
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
    return FlatContainer(
      radius: 24,
      filled: false,
      accent: accent,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TablerIcons.waveSine,
              size: 42,
              color: FathomColors.onSurface.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading equalizer',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The equalizer will appear once it initializes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: FathomColors.onSurface.withValues(alpha: 0.5),
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
                      ? FathomColors.onSurface.withValues(alpha: 0.35)
                      : accent,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FlatSlider(
                  vertical: true,
                  value: (gain - minDb) / (maxDb - minDb),
                  origin: -minDb / (maxDb - minDb),
                  color: accent,
                  onChanged: (t) => player.setBandGain(
                    band.centerFrequency.round(),
                    minDb + t * (maxDb - minDb),
                  ),
                  onChangeEnd: (t) => player.setBandGain(
                    band.centerFrequency.round(),
                    minDb + t * (maxDb - minDb),
                    persist: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                frequencyLabel(band.centerFrequency.round()),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  color: FathomColors.onSurface.withValues(alpha: 0.4),
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

/// Horizontal preamp control shown above the ten vertical bands.
///
/// Mirrors the band columns: `FathomSettings.stageEqPreamp` does not notify
/// listeners, so the value is held locally and re-read from the model whenever
/// the page rebuilds (presets, resets, toggling the equalizer).
class _PreampRow extends StatefulWidget {
  const _PreampRow({required this.accent});

  final Color accent;

  @override
  State<_PreampRow> createState() => _PreampRowState();
}

class _PreampRowState extends State<_PreampRow> {
  static const double _max = FathomNativeEqualizer.maxPreampDecibels;

  double _db = 0;

  @override
  void initState() {
    super.initState();
    _db = _storedDb();
  }

  @override
  void didUpdateWidget(covariant _PreampRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _db = _storedDb();
  }

  double _storedDb() =>
      context.read<FathomSettings>().eqPreamp.clamp(-_max, _max).toDouble();

  void _onChanged(double t) {
    final db = t * 2 * _max - _max;
    setState(() => _db = db);
    context.read<FathomPlayer>().setPreamp(db);
  }

  void _onChangeEnd(double t) {
    context.read<FathomPlayer>().setPreamp(t * 2 * _max - _max, persist: true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final db = _db;
    final sign = db > 0.05 ? '+' : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(TablerIcons.adjustmentsHorizontal, size: 16, color: accent),
            const SizedBox(width: 10),
            Text(
              'Preamp',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: FlatSlider(
                value: (db + _max) / (2 * _max),
                origin: 0.5,
                color: accent,
                onChanged: _onChanged,
                onChangeEnd: _onChangeEnd,
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 40,
              child: Text(
                '$sign${db.toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: db.abs() < 0.05
                      ? FathomColors.onSurface.withValues(alpha: 0.35)
                      : accent,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NativeBandColumn extends StatefulWidget {
  const _NativeBandColumn({
    required this.index,
    required this.centerFrequency,
    required this.minDb,
    required this.maxDb,
    required this.accent,
  });

  final int index;
  final int centerFrequency;
  final double minDb;
  final double maxDb;
  final Color accent;

  @override
  State<_NativeBandColumn> createState() => _NativeBandColumnState();
}

class _NativeBandColumnState extends State<_NativeBandColumn> {
  /// Local mirror of the stored gain.
  ///
  /// `FathomSettings.stageEqGain` deliberately does not notify listeners, so the
  /// column cannot rely on a provider rebuild while the user drags. It keeps the
  /// value itself and re-reads the model whenever the page rebuilds (presets,
  /// resets, toggling the equalizer).
  double _gain = 0;

  @override
  void initState() {
    super.initState();
    _gain = _storedGain();
  }

  @override
  void didUpdateWidget(covariant _NativeBandColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gain = _storedGain();
  }

  double _storedGain() {
    final stored =
        context.read<FathomSettings>().eqGains[widget.centerFrequency];
    return (stored ?? 0.0).clamp(widget.minDb, widget.maxDb).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final hz = widget.centerFrequency;
    final accent = widget.accent;
    final gain = _gain;
    final sign = gain > 0.05 ? '+' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Text(
            '$sign${gain.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: gain.abs() < 0.05
                  ? FathomColors.onSurface.withValues(alpha: 0.35)
                  : accent,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FlatSlider(
              vertical: true,
              value: (gain - widget.minDb) / (widget.maxDb - widget.minDb),
              origin: -widget.minDb / (widget.maxDb - widget.minDb),
              color: accent,
              onChanged: (t) {
                final db = widget.minDb + t * (widget.maxDb - widget.minDb);
                setState(() => _gain = db);
                context.read<FathomPlayer>().setBandGain(hz, db);
              },
              onChangeEnd: (t) {
                final db = widget.minDb + t * (widget.maxDb - widget.minDb);
                context.read<FathomPlayer>().setBandGain(hz, db, persist: true);
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            frequencyLabel(hz),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              color: FathomColors.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
