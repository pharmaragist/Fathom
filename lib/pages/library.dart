import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/library.dart';
import '../common/player.dart';
import '../common/settings.dart';
import '../common/states.dart';
import '../components/art.dart';
import '../components/flat_icon_button.dart';
import '../components/glass.dart';
import '../components/styled_list_view.dart';
import '../models/tracks.dart';
import 'playing.dart' show NowPlayingPage;
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

final _letterPattern = RegExp(r'\p{L}', unicode: true);
final _whitespacePattern = RegExp(r'\s+');

List<FathomTrack> _sortedBy<K extends Comparable<dynamic>>(
  List<FathomTrack> source,
  K Function(FathomTrack) key, {
  bool descending = false,
}) {
  final keyed = [for (final t in source) (t, key(t))];
  keyed.sort(
    (a, b) => descending ? b.$2.compareTo(a.$2) : a.$2.compareTo(b.$2),
  );
  return [for (final e in keyed) e.$1];
}

List<FathomTrack> _sorted(List<FathomTrack> source, LibrarySort sort) {
  return switch (sort) {
    LibrarySort.titleAsc => _sortedBy(source, (t) => t.title.toLowerCase()),
    LibrarySort.titleDesc => _sortedBy(source, (t) => t.title.toLowerCase(), descending: true),
    LibrarySort.artistAsc => _sortedBy(
        source,
        (t) => '${t.artist.toLowerCase()}\u0000${t.title.toLowerCase()}',
      ),
    LibrarySort.newest => _sortedBy(source, (t) => t.dateAdded ?? t.id, descending: true),
    LibrarySort.oldest => _sortedBy(source, (t) => t.dateAdded ?? t.id),
  };
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
  return _letterPattern.hasMatch(first) ? first.toUpperCase() : '#';
}

Route<void> nowPlayingRoute() {
  return PageRouteBuilder<void>(
    fullscreenDialog: true,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => const NowPlayingPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: child,
      );
    },
  );
}

Route<void> _settingsRoute() {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const SettingsPage(),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    ),
  );
}

Future<void> chooseSortBottomSheet(
  BuildContext context,
  Color accent,
  LibrarySort currentSort,
) async {
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

  if (picked == null || picked == currentSort || !context.mounted) return;
  context.read<FathomSettings>().set(SettingKey.sortIndex, picked.index);
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final ScrollController _scroll = ScrollController();

  List<FathomTrack>? _sortedSource;
  LibrarySort? _sortedWith;
  List<FathomTrack> _sortedList = const [];
  Map<int, String> _haystacks = const {};

  List<FathomTrack>? _resultSortedFrom;
  String? _resultQuery;
  List<FathomTrack> _result = const [];

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
    _scroll.dispose();
    super.dispose();
  }

  List<FathomTrack> _visibleTracks(
    List<FathomTrack> source,
    LibrarySort sort,
    String rawQuery,
  ) {
    if (!identical(source, _sortedSource)) {
      _haystacks = {
        for (final t in source) t.id: '${t.title} ${t.artist}'.toLowerCase(),
      };
      _sortedSource = source;
      _sortedWith = null;
    }

    if (_sortedWith != sort) {
      _sortedList = _sorted(source, sort);
      _sortedWith = sort;
      _resultSortedFrom = null;
    }

    final query = rawQuery.trim().toLowerCase();
    if (identical(_resultSortedFrom, _sortedList) && _resultQuery == query) {
      return _result;
    }

    _resultSortedFrom = _sortedList;
    _resultQuery = query;

    if (query.isEmpty) return _result = _sortedList;

    final tokens = query.split(_whitespacePattern);
    return _result = _sortedList.where((t) {
      final hay = _haystacks[t.id] ?? '';
      return tokens.every(hay.contains);
    }).toList(growable: false);
  }

  void _play(List<FathomTrack> tracks, int index) {
    final player = context.read<FathomPlayer>();
    final navigator = Navigator.of(context);
    final started = player.playFrom(tracks, index);
    navigator.push(nowPlayingRoute());
    started.then((ok) {
      if (!ok && navigator.mounted) navigator.maybePop();
    });
  }

  Widget _stateView(
    FathomLibraryStatus status,
    bool libraryHasTracks,
    String query,
    Color accent,
  ) {
    return switch (status) {
      FathomLibraryStatus.idle || FathomLibraryStatus.loading => Center(
          child: CircularProgressIndicator(color: accent),
        ),
      FathomLibraryStatus.permissionNeeded => _StatusInfo(
          icon: TablerIcons.music,
          title: 'Allow audio access',
          message: 'Fathom never uploads anything. The library is scanned locally on this device.',
          accent: accent,
          action: 'Grant access',
          onAction: () => context.read<FathomLibrary>().load(grantIfMissing: true),
        ),
      FathomLibraryStatus.failure => _StatusInfo(
          icon: TablerIcons.alertCircle,
          title: 'Scan failed',
          message: 'Fathom could not read the audio library.',
          accent: accent,
          action: 'Retry',
          onAction: () => context.read<FathomLibrary>().load(grantIfMissing: false),
        ),
      FathomLibraryStatus.ready when !libraryHasTracks => const _StatusInfo(
          icon: TablerIcons.music,
          title: 'Library is empty',
          message: 'Audio files will appear here once added to the device.',
        ),
      FathomLibraryStatus.ready => _StatusInfo(
          icon: TablerIcons.searchOff,
          title: 'No matches',
          message: 'Nothing found for "${query.trim()}".',
          accent: accent,
          action: 'Clear search',
          onAction: () => searchQuery.value = '',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select<FathomLibrary, FathomLibraryStatus>((l) => l.status);
    final source = context.select<FathomLibrary, List<FathomTrack>>((l) => l.tracks);
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final sortIndex = context.select<FathomSettings, int>(
      (s) => s.get<int>(SettingKey.sortIndex),
    );

    final sort = LibrarySort.values[sortIndex.clamp(0, LibrarySort.values.length - 1)];
    final viewPadding = MediaQuery.viewPaddingOf(context);

    const header = Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: _Header(),
    );

    return ValueListenableBuilder<String>(
      valueListenable: searchQuery,
      builder: (context, query, _) {
        final ready = status == FathomLibraryStatus.ready;
        final tracks = ready ? _visibleTracks(source, sort, query) : const <FathomTrack>[];
        final showsList = tracks.isNotEmpty;

        return Padding(
          padding: EdgeInsets.only(top: viewPadding.top + 8),
          child: showsList
              ? StyledListView<FathomTrack>(
                  scrollController: _scroll,
                  header: header,
                  items: tracks,
                  accent: accent,
                  bottomInset: viewPadding.bottom + 150,
                  labelFor: (i) => _labelFor(tracks, sort, i),
                  itemBuilder: (context, track, i, height) => TrackTile(
                    track: track,
                    height: height,
                    onTap: () => _play(tracks, i),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    Expanded(child: _stateView(status, source.isNotEmpty, query, accent)),
                  ],
                ),
        );
      },
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
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final isPlaying = context.select<FathomPlayer, bool>(
      (p) => p.currentTrack?.id == track.id,
    );
    final library = context.read<FathomLibrary>();

    final compact = height <= 48.0;
    final artSize = (height - 12.0).clamp(24.0, 68.0);
    final indicatorHeight = compact ? 14.0 : artSize - 8.0;

    final titleStyle = TextStyle(
      fontSize: compact ? 15 : 16,
      height: compact ? 1.0 : 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: isPlaying ? accent : Colors.white,
    );
    final artistStyle = TextStyle(
      fontSize: compact ? 12.5 : 12,
      height: compact ? 1.0 : 1.15,
      color: Colors.white.withValues(alpha: compact ? 0.45 : 0.5),
    );

    final title = Text(
      track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );
    final artist = Text(
      track.artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: artistStyle,
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: () {
              heroFromPanel.value = compact;
              onTap();
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.only(
                left: compact ? 16 : 20,
                right: compact ? 12 : 16,
              ),
              child: Row(
                children: [
                  if (!compact) ...[
                    ValueListenableBuilder<bool>(
                      valueListenable: heroFromPanel,
                      builder: (context, fromPanel, child) =>
                          HeroMode(enabled: !fromPanel, child: child!),
                      child: Hero(
                        tag: 'fathom-art-${track.id}',
                        child: ArtThumb(
                          id: track.id,
                          artwork: library.artFor(track.id),
                          size: artSize,
                          radius: artSize > 42 ? 18 : 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: compact
                        ? Row(
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 14),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: artist,
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 4),
                              artist,
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (isPlaying)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: IgnorePointer(
                child: Center(
                  child: SizedBox(
                    height: indicatorHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
            'Fathom',
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
        FlatIconButton(
          icon: TablerIcons.settings,
          size: 22,
          padding: const EdgeInsets.all(8),
          color: Colors.white,
          onTap: () => Navigator.of(context).push(_settingsRoute()),
        ),
      ],
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
                onTap: () => Navigator.of(context).pop(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: option == current ? FontWeight.w700 : FontWeight.w500,
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
    final accent = this.accent;
    final action = this.action;

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
                child: GlassContainer(
                  radius: 99,
                  bgOpacity: 0.4,
                  accent: accent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(
                        action,
                        style: TextStyle(color: accent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
