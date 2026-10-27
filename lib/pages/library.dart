import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/library_diff.dart';
import '../common/motion.dart';
import '../common/player.dart';
import '../common/search.dart';
import '../common/selection.dart';
import '../common/settings.dart';
import '../components/art.dart';
import '../components/glass.dart';
import '../components/styled_list_view.dart';
import '../components/track_actions.dart';
import '../components/track_text_morph.dart';
import '../models/tracks.dart';
import '../models/ytmusic.dart';
import '../services/downloads.dart';
import '../services/yt_source.dart';
import 'playing.dart' show NowPlayingPage;

/// Row heights the library's pinch and double-tap zoom cycle through.
///
/// Kept here rather than in the list so the list remains a generic scrolling
/// primitive: it owns the gesture and the snap, the library owns what its rows
/// do at each stage.
const List<double> kLibraryRowHeights = [38.0, 64.0, 90.0, 118.0];

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
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) =>
        const NowPlayingPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Reduced motion: the shared elements have nowhere to fly, so the page
      // swaps directly rather than fading over a stalled hero.
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = animation.drive(
        CurveTween(curve: const FathomSpringCurve()),
      );
      // Only the page fades. The art and the words travel through their own
      // heroes, so a slide here would move the destination out from under
      // them for the whole flight.
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

Future<void> chooseSortBottomSheet(
  BuildContext context,
  Color accent,
  LibrarySort currentSort,
) async {
  final picked = await showModalBottomSheet<LibrarySort>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: FathomColors.scrim,
    sheetAnimationStyle: kModalMotion,
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
  const LibraryPage({super.key, required this.selection});

  /// The shell's selection mode. The header and the rows read the same
  /// controller so a row tap and the contextual title cannot disagree.
  final FathomSelection selection;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final ScrollController _scroll = ScrollController();

  /// Raised while a remote result's tap is fetching it, so a second tap on the
  /// same row is ignored instead of starting an overlapping fetch the download
  /// service would only refuse anyway.
  final Set<String> _fetching = <String>{};

  /// Whether yt results have been loaded for the current query.
  bool _ytLoaded = false;

  /// Memo key for the sorted list. The source is only re-keyed when the
  /// library publishes a new revision, and only re-sorted when the sort mode
  /// changes — an unrelated rebuild (accent, keyboard, settings) reuses both.
  int _sortedRevision = -1;
  LibrarySort? _sortedWith;
  List<FathomTrack> _sortedList = const [];
  Map<int, String> _haystacks = const {};

  List<FathomTrack>? _resultSortedFrom;
  String? _resultQuery;
  List<FathomTrack> _result = const [];

  /// The local results merged with the current remote ones, memoised by the
  /// two input lists. A build that changes neither gets the same list instance,
  /// so `StyledListView` can see that the row set is unchanged.
  List<FathomTrack>? _mergedLocal;
  List<FathomTrack>? _mergedRemote;
  List<FathomTrack> _merged = const [];

  /// Row widgets keyed by track identity, so a scan that leaves a row's data
  /// alone leaves its element alone. A row is only rebuilt when its track
  /// object changes (the library reuses the old instance when metadata is
  /// unchanged) or its fetch state changes.
  final Map<LibraryTrackKey, _CachedRow> _rowCache = {};
  double? _rowHeight;

  /// The palette the cached rows were built against.
  ///
  /// `FathomColors` is a set of statics, not an inherited widget: a theme or
  /// scheme change repaints from the root but does not make a cached row
  /// rebuild itself. Clearing when either changes is what keeps a cached row
  /// from wearing the previous theme's text colors.
  Object? _rowPalette;

  /// The list the current row callbacks act on. Kept because a cached row's
  /// tap cannot capture a build-time list without pinning this build's data.
  List<FathomTrack> _currentTracks = const [];

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
    widget.selection.addListener(_onSelectionChanged);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FathomLibrary>().load(grantIfMissing: false);
      // A query can survive a rebuild, so treat a restored one as a fresh
      // keystroke rather than leaving the remote half empty.
      _onQueryChanged();
    });
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _query?.removeListener(_onQueryChanged);
    _ytDebounce?.cancel();
    unawaited(_ytSub?.cancel());
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Repaints only the rows and list chrome that show selection state.
  ///
  /// The row cache compares these flags, so a selection change rebuilds the
  /// affected rows and leaves every untouched row's widget alone.
  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged() {
    // A selection describes the list the user was looking at. Editing the
    // query replaces that list, so the mode is dropped before the remote half
    // is reset. Entering selection mode itself does not change the query.
    if (widget.selection.active) widget.selection.exit();

    // Cached remote rows belong to the query that produced them; keeping them
    // across keystrokes would accumulate a dead result set per search. Local
    // rows are kept: they are what a stable scroll position is made of.
    _rowCache.removeWhere(
      (_, row) => row.track.origin == TrackOrigin.ytMusic,
    );
    final query = context.read<FathomSearch>().query.value.trim();
    _ytDebounce?.cancel();
    if (query.isEmpty) {
      _ytToken++;
      unawaited(_ytSub?.cancel());
      _ytSub = null;
      _ytLoaded = false;
      if (_ytResults.isNotEmpty || _ytSearching || _ytError != null) {
        setState(() {
          _ytResults = const [];
          _ytSearching = false;
          _ytError = null;
        });
      } else {
        _ytResults = const [];
        _ytSearching = false;
        _ytError = null;
      }
      return;
    }
    _ytToken++;
    unawaited(_ytSub?.cancel());
    _ytSub = null;
    _ytLoaded = false;
    setState(() {
      _ytResults = const [];
      _ytSearching = false;
      _ytError = null;
    });

    // A keystroke is not a search yet. The native extractor resolves a whole
    // page in one call, so firing on every character both wastes requests and
    // arrives with the token of a query the user has already moved past. One
    // pause is the whole debounce; the field below the list keeps showing the
    // device matches meanwhile.
    _ytDebounce?.cancel();
    _ytDebounce = Timer(const Duration(milliseconds: 350), () {
      _ytDebounce = null;
      if (!mounted) return;
      final current = context.read<FathomSearch>().query.value.trim();
      if (current.isEmpty || _ytSearching) return;
      _ytLoaded = true;
      unawaited(_runSearch(current));
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) {
      // Not scrollable yet; try to load if conditions met
      _maybeLoadYtOnScroll();
      return;
    }
    if (position.pixels >= position.maxScrollExtent - 200) {
      _maybeLoadYtOnScroll();
    }
  }

  void _maybeLoadYtOnScroll() {
    if (_ytLoaded || _ytSearching) return;
    final query = context.read<FathomSearch>().query.value.trim();
    if (query.isEmpty) return;
    _ytLoaded = true;
    _runSearch(query);
  }

  Future<void> _runSearch(String query) async {
    final token = ++_ytToken;
    final downloads = context.read<FathomDownloads>();
    final source = downloads.source;
    final thrifty =
        context.read<FathomSettings>().get<bool>(SettingKey.dataSave);

    if (!source.isReady) {
      await source.retry();
      if (!mounted || token != _ytToken) return;
      if (!source.isReady) {
        setState(() => _ytError = source.error ?? 'YouTube Music is down');
        return;
      }
    }

    if (mounted) {
      setState(() {
        _ytError = null;
        _ytSearching = true;
        _ytResults = const [];
      });
    } else {
      _ytError = null;
      _ytSearching = true;
      _ytResults = const [];
    }

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
        if (mounted && token == _ytToken) {
          // A fresh snapshot, not the growing buffer: the merge below compares
          // list identity, so reusing `collected` would freeze the remote half
          // at its first row whenever the device half matched too.
          setState(
              () => _ytResults = List<FathomTrack>.unmodifiable(collected));
        }
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
    int revision,
    LibrarySort sort,
    String rawQuery,
  ) {
    // The revision is the library's "the content changed" signal. Using it
    // rather than list identity keeps this honest: a scan that changes only a
    // title publishes a new snapshot but the same identities, and the old
    // identity check would have skipped the re-sort.
    if (_sortedRevision != revision) {
      _haystacks = {
        for (final t in source) t.id: '${t.title} ${t.artist}'.toLowerCase(),
      };
      _sortedRevision = revision;
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

  /// Merges the two search halves only when either half actually changed.
  List<FathomTrack> _mergeRemote(
    List<FathomTrack> local,
    List<FathomTrack> remote,
  ) {
    if (remote.isEmpty) return local;
    if (local.isEmpty) return remote;
    if (identical(local, _mergedLocal) && identical(remote, _mergedRemote)) {
      return _merged;
    }
    _mergedLocal = local;
    _mergedRemote = remote;
    return _merged = <FathomTrack>[...local, ...remote];
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
    final started = player.playFrom(tracks, index);
    navigator.push(nowPlayingRoute());
    started.then((ok) {
      if (ok || !navigator.mounted) return;
      try {
        navigator.maybePop();
      } catch (_) {}
    });
  }

  /// What a tap on a row means.
  ///
  /// A remote result has no audio to play, so its tap fetches it instead; it
  /// becomes a playable device track the moment the file lands and the list
  /// rescans, and the *next* tap plays it. The long-press menu keeps the honest
  /// names for both.
  void _activate(FathomTrack track) {
    // While selecting, a row tap belongs to the selection, not playback. A
    // remote result has no file a batch action could touch, so it is inert
    // rather than starting a download behind the selection UI.
    if (widget.selection.active) {
      widget.selection.toggle(track);
      return;
    }
    if (track.origin == TrackOrigin.device) {
      _playTrack(track);
    } else {
      unawaited(_fetch(track));
    }
  }

  /// Plays [track] in the context of the list currently on screen.
  ///
  /// The index is resolved at tap time rather than captured per build: row
  /// widgets are cached across builds, and a cached closure cannot hold a list
  /// from an older query without playing the wrong context.
  void _playTrack(FathomTrack track) {
    final tracks = _currentTracks;
    final index = tracks.indexOf(track);
    if (index < 0) return;
    _play(tracks, index);
  }

  Key _rowKeyFor(FathomTrack track) =>
      ValueKey<LibraryTrackKey>(libraryTrackKey(track));

  /// The row widget for [track] at [height], reused when nothing it renders has
  /// changed.
  ///
  /// The library's reconciler hands back the same [FathomTrack] instance when a
  /// scan leaves its metadata alone, so object identity is a sufficient "this
  /// row's data is unchanged" token. The only other input is the fetch flag.
  /// Height is not part of the cache because the list animates it; any change
  /// clears the cache, and once the resize settles the rows are cached again.
  Widget _row(FathomTrack track, double height) {
    final palette = FathomColors.brightness;
    if (_rowHeight != height || _rowPalette != palette) {
      _rowCache.clear();
      _rowHeight = height;
      _rowPalette = palette;
    }
    final key = libraryTrackKey(track);
    final fetching = track.videoId != null && _fetching.contains(track.videoId);
    final selecting = widget.selection.active;
    final selected = widget.selection.isSelected(track);
    final cached = _rowCache[key];
    if (cached != null &&
        identical(cached.track, track) &&
        cached.fetching == fetching &&
        cached.selecting == selecting &&
        cached.selected == selected) {
      return cached.widget;
    }
    final row = TrackTile(
      track: track,
      height: height,
      fetching: fetching,
      selecting: selecting,
      selected: selected,
      onTap: () => _activate(track),
      onLongPress: () {
        // Standard selection behaviour: a long press on a device row enters
        // selection mode with that row already chosen. While the mode is on it
        // toggles the row, so the gesture stays useful for adjusting a set.
        // A remote item has no file a batch action could touch, so its long
        // press keeps the per-track menu that can download it.
        if (track.origin == TrackOrigin.device) {
          widget.selection.toggle(track);
          return;
        }
        showTrackActions(
          context,
          track,
          onPlay: () => _playTrack(track),
        );
      },
    );
    _rowCache[key] = _CachedRow(
      track,
      fetching,
      selecting,
      selected,
      row,
    );
    return row;
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
    // The revision is the page's wake-up signal; the list itself is read
    // without a selector because `tracks` is a snapshot whose elements compare
    // by identity alone, which would miss a metadata-only rescan.
    final revision = context.select<FathomLibrary, int>((l) => l.revision);
    final library = context.read<FathomLibrary>();
    final source = library.tracks;
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
        final local = ready
            ? _visibleTracks(source, revision, sort, query)
            : const <FathomTrack>[];
        // Remote results tail the local ones so one field searches both
        // collections. They are a list of things to *get*, not a second half of
        // a play queue: only a downloaded file can play.
        final tracks = searching ? _mergeRemote(local, _ytResults) : local;
        _currentTracks = tracks;
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
                zoomStages: kLibraryRowHeights,
                initialItemHeight: 90.0,
                minItemHeight: kLibraryRowHeights.first,
                maxItemHeight: kLibraryRowHeights.last,
                bottomInset: viewPadding.bottom + 150,
                sectionFor: sectionFor,
                labelFor: (i) => _labelFor(tracks, sort, i),
                keyFor: (i) => _rowKeyFor(tracks[i]),
                itemBuilder: (context, track, i, height) => _row(track, height),
              );
      },
    );
  }
}

/// One cached row widget, with the inputs that can invalidate it.
class _CachedRow {
  const _CachedRow(
    this.track,
    this.fetching,
    this.selecting,
    this.selected,
    this.widget,
  );

  final FathomTrack track;
  final bool fetching;
  final bool selecting;
  final bool selected;
  final Widget widget;
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.height,
    required this.onTap,
    this.onLongPress,
    this.fetching = false,
    this.selecting = false,
    this.selected = false,
  });

  final FathomTrack track;
  final double height;
  final VoidCallback onTap;

  /// The library's per-track action sheet; surfaces that keep their rows
  /// simple pass null.
  final VoidCallback? onLongPress;

  /// True while a tap on this remote row is fetching it, so the row can show
  /// the fetch in flight rather than looking inert.
  final bool fetching;

  /// Whether the library is in multi-select mode. Selection is a library mode,
  /// not a per-row one, so this is false on every surface that has no batch
  /// actions to offer.
  final bool selecting;

  /// Whether this row's device track is in the current selection.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final isPlaying = context.select<FathomPlayer, bool>(
      (p) => p.currentTrack?.id == track.id,
    );
    final library = context.read<FathomLibrary>();
    // Only a device track can play; a remote row's tap fetches it, and the row
    // says so rather than offering a play that would fail.
    final playable = track.origin == TrackOrigin.device;
    final zoom = StyledListZoom.maybeOf(context);

    // One continuous ramp across the whole zoom ladder. Nothing here switches
    // layout at a height threshold: a pinch that stops between stages still
    // paints a row that matches the extent it was given.
    final t = ((height - kLibraryRowHeights.first) /
            (kLibraryRowHeights.last - kLibraryRowHeights.first))
        .clamp(0.0, 1.0);
    final artSize = lerpDouble(24, 92, t)!;
    final artRadius = lerpDouble(6, 22, t)!;
    final indicatorHeight = (artSize - 8).clamp(14.0, 84.0).toDouble();
    final titleSize = lerpDouble(14, 18, t)!;
    final artistSize = lerpDouble(10.5, 13, t)!;
    final titleHeight = lerpDouble(1.0, 1.2, t)!;
    final artistHeight = lerpDouble(1.0, 1.15, t)!;
    final gap = lerpDouble(2, 4, t)!;
    final artGap = lerpDouble(10, 14, t)!;
    final leftPadding = lerpDouble(16, 20, t)!;
    final rightPadding = lerpDouble(12, 16, t)!;

    final titleStyle = TextStyle(
      fontSize: titleSize,
      height: titleHeight,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: isPlaying ? accent : FathomColors.onSurface,
    );
    final artistStyle = TextStyle(
      fontSize: artistSize,
      height: artistHeight,
      color: FathomColors.onSurface.withValues(
        alpha: lerpDouble(0.45, 0.5, t)!,
      ),
    );

    final morph = TrackTextMorph(
      title: track.title,
      artist: track.artist,
      titleStyle: titleStyle,
      artistStyle: artistStyle,
      gap: gap,
    );

    return Material(
      type: MaterialType.transparency,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: onTap,
                // A double-tap recognizer holds the single tap for its
                // timeout. In selection mode every tap is a selection toggle,
                // so the zoom gesture is removed and the row answers on the
                // tap itself instead of 300ms later.
                onDoubleTap: selecting ? null : zoom?.onDoubleTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: leftPadding,
                    right: rightPadding,
                  ),
                  child: Row(
                    children: [
                      // Only a device track can play, so only a device row
                      // advertises the cover and text tags: a remote result
                      // fetches on tap and never opens Now Playing.
                      if (playable)
                        Hero(
                          tag: 'fathom-art-${track.id}',
                          child: TrackArt(
                            library: library,
                            track: track,
                            size: artSize,
                            radius: artRadius,
                          ),
                        )
                      else
                        TrackArt(
                          library: library,
                          track: track,
                          size: artSize,
                          radius: artRadius,
                        ),
                      SizedBox(width: artGap),
                      Expanded(
                        child: playable
                            ? Hero(
                                tag: 'fathom-text-${track.id}',
                                flightShuttleBuilder: trackTextHeroShuttle,
                                child: morph,
                              )
                            : morph,
                      ),
                      if (!playable) ...[
                        const SizedBox(width: 10),
                        if (fetching)
                          SizedBox(
                            width: lerpDouble(13, 15, t),
                            height: lerpDouble(13, 15, t),
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: accent,
                            ),
                          )
                        else
                          Icon(
                            TablerIcons.cloudDownload,
                            size: lerpDouble(13, 15, t),
                            color:
                                FathomColors.onSurface.withValues(alpha: 0.35),
                          ),
                      ],
                      // Only device rows can enter a batch action, so only
                      // they show a selection affordance. The check is the
                      // trailing control of the row; the playing bar stays on
                      // the leading edge.
                      if (selecting && playable) ...[
                        const SizedBox(width: 8),
                        Icon(
                          selected
                              ? TablerIcons.circleCheckFilled
                              : TablerIcons.circle,
                          size: lerpDouble(18, 22, t),
                          color: selected
                              ? accent
                              : FathomColors.onSurface.withValues(alpha: 0.30),
                        ),
                      ],
                    ],
                  ),
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
