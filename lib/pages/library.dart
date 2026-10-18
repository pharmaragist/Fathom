import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../states.dart';
import '../components/art.dart';
import '../components/glass.dart';
import 'settings.dart';

enum LibrarySort {
  titleAsc('Title A–Z'),
  titleDesc('Title Z–A'),
  artistAsc('Artist A–Z'),
  newest('Newest first'),
  oldest('Oldest first');

  const LibrarySort(this.label);

  final String label;
}

int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String _query = '';
  List<FathomTrack> _cachedDisplayTracks = const [];
  List<FathomTrack>? _lastRawTracks;
  LibrarySort? _lastSort;
  String _lastQuery = '';

  static const double _minTileHeight = 38.0;
  static const double _maxTileHeight = 90.0;
  double _itemHeight = _maxTileHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FathomLibrary>().load(grantIfMissing: false);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<FathomTrack> _getProcessedTracks(
    List<FathomTrack> rawTracks,
    LibrarySort sort,
  ) {
    if (identical(rawTracks, _lastRawTracks) &&
        sort == _lastSort &&
        _query == _lastQuery) {
      return _cachedDisplayTracks;
    }

    final list = List<FathomTrack>.of(rawTracks);
    switch (sort) {
      case LibrarySort.titleAsc:
        list.sort((a, b) => _cmp(a.title, b.title));
      case LibrarySort.titleDesc:
        list.sort((a, b) => _cmp(b.title, a.title));
      case LibrarySort.artistAsc:
        list.sort((a, b) {
          final c = _cmp(a.artist, b.artist);
          return c != 0 ? c : _cmp(a.title, b.title);
        });
      case LibrarySort.newest:
        list.sort(
            (a, b) => (b.dateAdded ?? b.id).compareTo(a.dateAdded ?? a.id));
      case LibrarySort.oldest:
        list.sort(
            (a, b) => (a.dateAdded ?? a.id).compareTo(b.dateAdded ?? b.id));
    }

    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      _cachedDisplayTracks = list;
    } else {
      final tokens = q.split(RegExp(r'\s+'));
      _cachedDisplayTracks = list.where((t) {
        final hay = '${t.title} ${t.artist}'.toLowerCase();
        return tokens.every(hay.contains);
      }).toList();
    }

    _lastRawTracks = rawTracks;
    _lastSort = sort;
    _lastQuery = _query;
    return _cachedDisplayTracks;
  }

  String? _labelFor(List<FathomTrack> tracks, LibrarySort sort, int i) {
    if (i < 0 || i >= tracks.length) return null;
    final source = switch (sort) {
      LibrarySort.titleAsc || LibrarySort.titleDesc => tracks[i].title,
      LibrarySort.artistAsc => tracks[i].artist,
      _ => null,
    };
    final text = source?.trim() ?? '';
    if (text.isEmpty) return null;
    final first = String.fromCharCode(text.runes.first);
    if (RegExp(r'\p{L}', unicode: true).hasMatch(first)) {
      return first.toUpperCase();
    }
    return '#';
  }

  void _onQuery(String v) {
    setState(() => _query = v);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _clearQuery() {
    _search.clear();
    _onQuery('');
  }

  Future<void> _chooseSort(Color accent, LibrarySort currentSort) async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<LibrarySort>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GlassContainer(
            radius: 28,
            accent: accent,
            shadow: true,
            child: _SortSheet(current: currentSort, accent: accent),
          ),
        ),
      ),
    );
    if (picked == null || picked == currentSort || !mounted) return;
    context.read<FathomSettings>().setSortIndex(picked.index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final status =
        context.select<FathomLibrary, FathomLibraryStatus>((l) => l.status);
    final rawTracks =
        context.select<FathomLibrary, List<FathomTrack>>((l) => l.tracks);
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final sortIndex = context.select<FathomSettings, int>((s) => s.sortIndex);

    final currentSort =
        LibrarySort.values[sortIndex.clamp(0, LibrarySort.values.length - 1)];

    final ready = status == FathomLibraryStatus.ready;
    final hasTracks = ready && rawTracks.isNotEmpty;
    final tracks = ready
        ? _getProcessedTracks(rawTracks, currentSort)
        : const <FathomTrack>[];

    final top = MediaQuery.viewPaddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    final Widget body = switch (status) {
      FathomLibraryStatus.idle || FathomLibraryStatus.loading =>
        Center(child: CircularProgressIndicator(color: accent)),
      FathomLibraryStatus.permissionNeeded => _StatusInfo(
          icon: TablerIcons.music,
          title: 'Allow audio access',
          message:
              'Fathom never uploads anything. The library is scanned locally on this device.',
          accent: accent,
          action: 'Grant access',
          onAction: () {
            context.read<FathomLibrary>().load(grantIfMissing: true);
          },
        ),
      FathomLibraryStatus.failure => _StatusInfo(
          icon: TablerIcons.alertCircle,
          title: 'Scan failed',
          message: 'Fathom could not read the audio library.',
          accent: accent,
          action: 'Retry',
          onAction: () =>
              context.read<FathomLibrary>().load(grantIfMissing: false),
        ),
      FathomLibraryStatus.ready when !hasTracks => const _StatusInfo(
          icon: TablerIcons.music,
          title: 'Library is empty',
          message: 'Audio files will appear here once added to the device.',
        ),
      FathomLibraryStatus.ready when tracks.isEmpty => _StatusInfo(
          icon: TablerIcons.searchOff,
          title: 'No matches',
          message: 'Nothing found for "${_query.trim()}".',
          accent: accent,
          action: 'Clear search',
          onAction: _clearQuery,
        ),
      FathomLibraryStatus.ready => GestureDetector(
          onDoubleTap: () => setState(() => _itemHeight = _maxTileHeight),
          onScaleUpdate: (details) {
            if (details.pointerCount < 2) return;
            if (details.scale < 0.85 && _itemHeight != _minTileHeight) {
              setState(() => _itemHeight = _minTileHeight);
            } else if (details.scale > 1.15 && _itemHeight != _maxTileHeight) {
              setState(() => _itemHeight = _maxTileHeight);
            }
          },
          child: _FastScrollbar(
            controller: _scroll,
            accent: accent,
            itemCount: tracks.length,
            topInset: 4,
            bottomInset: bottom + 130,
            labelFor: (i) => _labelFor(tracks, currentSort, i),
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, bottom + 150),
                  sliver: SuperSliverList.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, i) {
                      final track = tracks[i];
                      return TrackTile(
                        key: ValueKey(track.id),
                        track: track,
                        height: _itemHeight,
                        onTap: () {
                          Future.microtask(() {
                            if (!context.mounted) return;
                            context.read<FathomPlayer>().playFrom(tracks, i);
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
    };

    return Padding(
      padding: EdgeInsets.only(top: top + 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: _Header(),
          ),
          if (hasTracks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _SearchField(
                controller: _search,
                accent: accent,
                sortLabel: currentSort.label,
                onSort: () => _chooseSort(accent, currentSort),
                onChanged: _onQuery,
                onClear: _clearQuery,
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.height,
    required this.onTap,
  });

  final FathomTrack track;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.select<FathomPlayer, bool>(
      (p) => p.currentTrack?.id == track.id,
    );
    final accent = context.select<FathomSettings, Color>((s) => s.accent);

    final library = context.read<FathomLibrary>();
    final bool isCompact = height <= 48.0;
    final double artSize = (height - 12.0).clamp(24.0, 68.0).toDouble();

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: height,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16),
              child: Center(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutBack,
                      width: isPlaying ? 4 : 0,
                      height: isPlaying ? (isCompact ? 14 : artSize - 8) : 0,
                      margin: EdgeInsets.only(right: isPlaying ? 12 : 0),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        opacity: isPlaying ? 1.0 : 0.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    if (!isCompact) ...[
                      ArtThumb(
                        id: track.id,
                        artwork: library.artFor(track.id),
                        size: artSize,
                        radius: artSize > 42 ? 18 : 6,
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: isCompact
                          ? Row(
                              children: [
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.0,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: isPlaying ? accent : Colors.white,
                                    ),
                                    child: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.0,
                                    color: Colors.white.withValues(alpha: 0.45),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: isPlaying ? accent : Colors.white,
                                  ),
                                  child: Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.15,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            kAppName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.8,
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            Navigator.of(context).push(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 250),
                reverseTransitionDuration: const Duration(milliseconds: 200),
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const SettingsPage(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(1.0, 0.0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    ),
                  );

                  return SlideTransition(
                    position: slideAnimation,
                    child: child,
                  );
                },
              ),
            );
          },
          icon: const Icon(
            TablerIcons.settings,
            size: 22,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.accent,
    required this.sortLabel,
    required this.onSort,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final Color accent;
  final String sortLabel;
  final VoidCallback onSort;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(TablerIcons.search, size: 20, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              cursorColor: accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Search',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(TablerIcons.x, size: 18, color: muted),
                ),
              );
            },
          ),
          _SortBadge(
            label: sortLabel,
            accent: accent,
            onTap: onSort,
          ),
        ],
      ),
    );
  }
}

class _SortBadge extends StatelessWidget {
  const _SortBadge({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TablerIcons.arrowsSort, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current, required this.accent});

  final LibrarySort current;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Sort by',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
            ),
            for (final option in LibrarySort.values)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).pop(option);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: option == current
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: option == current ? accent : Colors.white,
                          ),
                        ),
                      ),
                      if (option == current)
                        Icon(TablerIcons.check, size: 20, color: accent),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FastScrollbar extends StatefulWidget {
  const _FastScrollbar({
    required this.controller,
    required this.accent,
    required this.itemCount,
    required this.labelFor,
    required this.child,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final ScrollController controller;
  final Color accent;
  final int itemCount;
  final String? Function(int index) labelFor;
  final Widget child;
  final double topInset;
  final double bottomInset;

  @override
  State<_FastScrollbar> createState() => _FastScrollbarState();
}

class _FastScrollbarState extends State<_FastScrollbar> {
  Timer? _hideTimer;
  bool _visible = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_FastScrollbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_dragging) setState(() => _visible = false);
    });
  }

  void _onScroll() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    if (!_dragging) _scheduleHide();
  }

  void _dragStart() {
    _hideTimer?.cancel();
    setState(() {
      _dragging = true;
      _visible = true;
    });
  }

  void _dragEnd() {
    setState(() => _dragging = false);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final shown = _visible || _dragging;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: widget.topInset,
          bottom: widget.bottomInset,
          right: 0,
          width: 40,
          child: IgnorePointer(
            ignoring: !shown,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: LayoutBuilder(
                builder: (context, c) {
                  final trackHeight = c.maxHeight;
                  return AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) {
                      if (!widget.controller.hasClients) {
                        return const SizedBox.shrink();
                      }
                      final pos = widget.controller.position;
                      if (!pos.hasContentDimensions ||
                          pos.maxScrollExtent <= 0) {
                        return const SizedBox.shrink();
                      }
                      final max = pos.maxScrollExtent;
                      final viewport = pos.viewportDimension;
                      final thumbHeight =
                          (trackHeight * viewport / (viewport + max))
                              .clamp(56.0, trackHeight)
                              .toDouble();
                      final range = trackHeight - thumbHeight;
                      final fraction =
                          (pos.pixels / max).clamp(0.0, 1.0).toDouble();
                      final thumbTop = fraction * range;
                      final index = (fraction * (widget.itemCount - 1)).round();
                      final label = _dragging ? widget.labelFor(index) : null;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (label != null)
                            Positioned(
                              top: thumbTop + thumbHeight / 2 - 26,
                              right: 44,
                              child: GlassContainer(
                                radius: 18,
                                bgOpacity: 0.85,
                                accent: accent,
                                shadow: true,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  alignment: Alignment.center,
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: onAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: thumbTop,
                            right: 0,
                            width: 40,
                            height: thumbHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: (_) => _dragStart(),
                              onVerticalDragUpdate: (d) {
                                if (range <= 0) return;
                                final next =
                                    (pos.pixels + d.delta.dy / range * max)
                                        .clamp(0.0, max)
                                        .toDouble();
                                widget.controller.jumpTo(next);
                              },
                              onVerticalDragEnd: (_) => _dragEnd(),
                              onVerticalDragCancel: _dragEnd,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: _dragging ? 8 : 4,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color: _dragging
                                        ? accent
                                        : Colors.white.withValues(alpha: 0.32),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 99,
      bgOpacity: 0.4,
      accent: accent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(
            label,
            style: TextStyle(color: accent, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _StatusInfo extends StatelessWidget {
  const _StatusInfo({
    required this.icon,
    required this.title,
    required this.message,
    this.accent,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? accent;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.35,
              ),
            ),
            if (action != null && onAction != null && accent != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: _PillButton(
                  label: action!,
                  accent: accent!,
                  onTap: onAction!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
