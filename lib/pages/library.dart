import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/player.dart';
import '../common/search.dart';
import '../common/settings.dart';
import '../common/toasts.dart';
import '../components/art.dart';
import '../components/glass.dart';
import '../components/styled_list_view.dart';
import '../components/track_actions.dart';
import '../models/tracks.dart';
import '../models/ytmusic.dart';
import '../services/downloads.dart';
import '../services/yt_source.dart';
import 'playing.dart' show NowPlayingPage;

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
    LibrarySort.titleDesc =>
      _sortedBy(source, (t) => t.title.toLowerCase(), descending: true),
    LibrarySort.artistAsc => _sortedBy(
        source,
        (t) => '${t.artist.toLowerCase()}\u0000${t.title.toLowerCase()}',
      ),
    LibrarySort.newest =>
      _sortedBy(source, (t) => t.dateAdded ?? t.id, descending: true),
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
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (context, animation, secondaryAnimation) =>
        const NowPlayingPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
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
    barrierColor: FathomColors.scrim,
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
  const LibraryPage({super.key, required this.heroFromPanel});

  /// Coordinates the now-playing hero with the mini player above; owned by
  /// the shell and handed to both sides.
  final ValueNotifier<bool> heroFromPanel;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final ScrollController _scroll = ScrollController();

  /// Raised while a remote result's tap is fetching it, so a second tap on the
  /// same row is ignored instead of starting an overlapping fetch the download
  /// service would only refuse anyway.
  final Set<String> _fetching = <String>{};

  List<FathomTrack>? _sortedSource;
  LibrarySort? _sortedWith;
  List<FathomTrack> _sortedList = const [];
  Map<int, String> _haystacks = const {};

  List<FathomTrack>? _resultSortedFrom;
  String? _resultQuery;
  List<FathomTrack> _result = const [];

  /// Remote results for the current query. They tail the device matches so
  /// one field searches both collections without a second screen.
  List<FathomTrack> _ytResults = const [];
  bool _ytSearching = false;
  String? _ytError;
  Timer? _ytDebounce;
  StreamSubscription<YtItem>? _ytSub;

  /// Bumped on every new query so results from a superseded stream are
  /// dropped instead of being appended to the new answer.
  int _ytToken = 0;

  /// The shared query notifier, captured while the element still has a
  /// provider above it.
  ///
  /// The page is a shell destination now, so it is disposed every time the
  /// shell leaves for another page. `dispose()` cannot reach a provider through
  /// `context` — the element is already deactivated by then — so the notifier it
  /// has to unsubscribe from is held here instead.
  ValueNotifier<String>? _query;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<FathomSearch>().query;
    if (identical(_query, next)) return;
    _query?.removeListener(_onQueryChanged);
    _query = next..addListener(_onQueryChanged);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FathomLibrary>().load(grantIfMissing: false);
      // A query can survive a rebuild, so treat a restored one as a fresh
      // keystroke rather than leaving the remote half empty.
      _onQueryChanged();
    });
  }

  @override
  void dispose() {
    _query?.removeListener(_onQueryChanged);
    _ytDebounce?.cancel();
    unawaited(_ytSub?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = context.read<FathomSearch>().query.value.trim();
    _ytDebounce?.cancel();
    if (query.isEmpty) {
      _ytToken++;
      unawaited(_ytSub?.cancel());
      _ytSub = null;
      _ytResults = const [];
      _ytSearching = false;
      _ytError = null;
      return;
    }
    _ytDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    final downloads = context.read<FathomDownloads>();
    final source = downloads.source;
    final thrifty =
        context.read<FathomSettings>().get<bool>(SettingKey.dataSave);

    if (!source.isReady) {
      await source.retry();
      if (!mounted) return;
      if (!source.isReady) {
        setState(() => _ytError = source.error ?? 'YouTube Music is down');
        return;
      }
    }

    final token = ++_ytToken;
    setState(() {
      _ytError = null;
      _ytSearching = true;
      _ytResults = const [];
    });

    final collected = <FathomTrack>[];
    final seen = <String>{};
    _ytSub = source
        .search(
      query,
      limit: thrifty ? 12 : 24,
      quality: thrifty ? YtQuality.low : YtQuality.high,
    )
        .listen(
      (item) {
        // A stream yields progressively, so guard the token per item; a
        // superseded search must never repaint the new one's list.
        if (token != _ytToken || !seen.add(item.videoId)) return;
        // Already on the device: it arrives with the local matches instead.
        if (downloads.isDone(item.videoId)) return;
        collected.add(FathomTrack.yt(item));
        setState(() => _ytResults = List.of(collected));
      },
      onError: (Object error) {
        if (token != _ytToken) return;
        // The stream carries the reason the search died; dropping it here
        // leaves the empty-state panel claiming "No matches" for a search that
        // never ran, which reads as a wrong answer rather than a failure.
        setState(() {
          _ytSearching = false;
          _ytError = error is PlatformException && error.code == 'RECAPTCHA'
              ? 'YouTube asked for a captcha before it would search'
              : 'YouTube search failed: $error';
        });
      },
      onDone: () {
        if (token != _ytToken) return;
        setState(() => _ytSearching = false);
      },
    );
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

  /// Fetches a remote search result, which is all a tap on one can mean.
  ///
  /// Playing it is a second tap, once the file exists: a remote item carries no
  /// address and nothing remote is streamed, so there is nothing to play yet.
  Future<void> _fetch(FathomTrack track) async {
    final videoId = track.videoId;
    if (videoId == null || !_fetching.add(videoId)) return;
    setState(() {});
    try {
      await downloadTrack(context, track);
    } finally {
      if (mounted) {
        setState(() => _fetching.remove(videoId));
      } else {
        _fetching.remove(videoId);
      }
    }
  }

  void _play(List<FathomTrack> tracks, int index) {
    final player = context.read<FathomPlayer>();
    final navigator = Navigator.of(context);
    // Captured before the frame the route push starts, because the report has
    // to be raised through a notifier that outlives this page: the page is a
    // shell destination and may already be gone by the time the play fails.
    final toasts = context.read<FathomToasts>();
    final started = player.playFrom(tracks, index);
    navigator.push(nowPlayingRoute());
    started.then((ok) {
      // A remote track can lose its address between search and play; the
      // player remembers why, and dropping the route silently would leave the
      // person staring at a paused player with no explanation.
      if (ok || !navigator.mounted) return;
      navigator.maybePop();
      final reason = player.lastError;
      toasts.show(
        'Could not play this track',
        detail: reason.isEmpty ? null : reason,
        icon: TablerIcons.alertTriangle,
        tone: ToastTone.failure,
      );
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
          message:
              'Fathom never uploads anything. The library is scanned locally on this device.',
          accent: accent,
          action: 'Grant access',
          onAction: () =>
              context.read<FathomLibrary>().load(grantIfMissing: true),
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
      FathomLibraryStatus.ready when !libraryHasTracks => const _StatusInfo(
          icon: TablerIcons.music,
          title: 'Library is empty',
          message: 'Audio files will appear here once added to the device.',
        ),
      FathomLibraryStatus.ready => _StatusInfo(
          icon: TablerIcons.searchOff,
          title: _ytError == null ? 'No matches' : 'YouTube search failed',
          message: _ytError != null
              ? _ytError!
              : 'Nothing found for "${query.trim()}" on this device or YouTube.',
          accent: accent,
          action: 'Clear search',
          onAction: () => context.read<FathomSearch>().clear(),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final search = context.read<FathomSearch>();
    final status =
        context.select<FathomLibrary, FathomLibraryStatus>((l) => l.status);
    final source =
        context.select<FathomLibrary, List<FathomTrack>>((l) => l.tracks);
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final sortIndex = context.select<FathomSettings, int>(
      (s) => s.get<int>(SettingKey.sortIndex),
    );

    final sort =
        LibrarySort.values[sortIndex.clamp(0, LibrarySort.values.length - 1)];
    final viewPadding = MediaQuery.viewPaddingOf(context);

    return ValueListenableBuilder<String>(
      valueListenable: search.query,
      builder: (context, query, _) {
        final ready = status == FathomLibraryStatus.ready;
        final searching = query.trim().isNotEmpty;
        final local =
            ready ? _visibleTracks(source, sort, query) : const <FathomTrack>[];
        // Remote results tail the local ones so one field searches both
        // collections. They are a list of things to *get*, not a second half of
        // a play queue: only a downloaded file can play.
        final tracks =
            searching ? <FathomTrack>[...local, ..._ytResults] : local;
        final showsList = tracks.isNotEmpty;

        String? sectionFor(int i) =>
            searching ? (i < local.length ? 'On device' : 'YouTube') : null;

        // The header belongs to the shell now, above this body, so the list
        // gets the whole layer and the shell's header stays reachable
        // however far the list has moved.
        return !showsList
            ? (_ytSearching
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : _stateView(status, source.isNotEmpty, query, accent))
            : StyledListView<FathomTrack>(
                scrollController: _scroll,
                items: tracks,
                accent: accent,
                bottomInset: viewPadding.bottom + 150,
                sectionFor: sectionFor,
                labelFor: (i) => _labelFor(tracks, sort, i),
                itemBuilder: (context, track, i, height) => TrackTile(
                  heroFromPanel: widget.heroFromPanel,
                  track: track,
                  height: height,
                  // A remote result has no audio to play, so its tap fetches it
                  // instead; it becomes a playable device track the moment the
                  // file lands and the list rescans, and the *next* tap plays
                  // it. The long-press menu keeps the honest names for both.
                  onTap: () => track.origin == TrackOrigin.device
                      ? _play(tracks, i)
                      : _fetch(track),
                  fetching: track.videoId != null &&
                      _fetching.contains(track.videoId),
                  onLongPress: () => showTrackActions(
                    context,
                    track,
                    onPlay: () => _play(tracks, i),
                  ),
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
    this.heroFromPanel,
    this.onLongPress,
    this.fetching = false,
  });

  final FathomTrack track;
  final double height;
  final VoidCallback onTap;

  /// Coordinates the now-playing hero with the mini player above. Surfaces
  /// that do not take part in the hero pass null.
  final ValueNotifier<bool>? heroFromPanel;

  /// The library's per-track action sheet; surfaces that keep their rows
  /// simple pass null.
  final VoidCallback? onLongPress;

  /// True while a tap on this remote row is fetching it, so the row can show
  /// the fetch in flight rather than looking inert.
  final bool fetching;

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final isPlaying = context.select<FathomPlayer, bool>(
      (p) => p.currentTrack?.id == track.id,
    );
    final library = context.read<FathomLibrary>();
    // A download becomes a device track the moment it lands, so the badge has
    // to answer for both: by row for a device track, by videoId for one that
    // is still remote.
    final downloaded = context.select<FathomDownloads, bool>(
      (d) => track.videoId != null
          ? d.isDone(track.videoId)
          : d.isDownloadedDeviceTrack(track.id),
    );
    // Only a device track can play; a remote row's tap fetches it, and the row
    // says so rather than offering a play that would fail.
    final playable = track.origin == TrackOrigin.device;

    final compact = height <= 48.0;
    final artSize = (height - 12.0).clamp(24.0, 68.0);
    final indicatorHeight = compact ? 14.0 : artSize - 8.0;

    final titleStyle = TextStyle(
      fontSize: compact ? 15 : 16,
      height: compact ? 1.0 : 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: isPlaying ? accent : FathomColors.onSurface,
    );
    final artistStyle = TextStyle(
      fontSize: compact ? 12.5 : 12,
      height: compact ? 1.0 : 1.15,
      color: FathomColors.onSurface.withValues(alpha: compact ? 0.45 : 0.5),
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
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: () {
                heroFromPanel?.value = compact;
                onTap();
              },
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.only(
                  left: compact ? 16 : 20,
                  right: compact ? 12 : 16,
                ),
                child: Row(
                  children: [
                    if (!compact) ...[
                      if (heroFromPanel == null)
                        TrackArt(
                          library: library,
                          track: track,
                          size: artSize,
                          radius: artSize > 42 ? 18 : 6,
                        )
                      else
                        ValueListenableBuilder<bool>(
                          valueListenable: heroFromPanel!,
                          builder: (context, fromPanel, child) =>
                              HeroMode(enabled: !fromPanel, child: child!),
                          child: Hero(
                            tag: 'fathom-art-${track.id}',
                            child: TrackArt(
                              library: library,
                              track: track,
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
                                  constraints:
                                      const BoxConstraints(maxWidth: 120),
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
                    if (downloaded) ...[
                      const SizedBox(width: 10),
                      Icon(
                        TablerIcons.cloudCheck,
                        size: compact ? 13 : 15,
                        color: FathomColors.onSurface.withValues(alpha: 0.3),
                      ),
                    ] else if (!playable) ...[
                      const SizedBox(width: 10),
                      if (fetching)
                        SizedBox(
                          width: compact ? 13 : 15,
                          height: compact ? 13 : 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: accent,
                          ),
                        )
                      else
                        Icon(
                          TablerIcons.cloudDownload,
                          size: compact ? 13 : 15,
                          color: FathomColors.onSurface.withValues(alpha: 0.35),
                        ),
                    ],
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Sort by',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: FathomColors.onSurface,
                ),
              ),
            ),
            for (final option in LibrarySort.values)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).pop(option),
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
                            color: option == current
                                ? accent
                                : FathomColors.onSurface,
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
            Icon(icon, size: 40, color: FathomColors.onSurfaceFaint),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: FathomColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: FathomColors.onSurface.withValues(alpha: 0.5),
                height: 1.35,
              ),
            ),
            if (action != null && onAction != null && accent != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                // The status block is page body content, not a floating
                // surface, so its action pill does not sample behind itself.
                child: FlatContainer(
                  radius: 99,
                  accent: accent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Text(
                        action,
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.w600),
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
