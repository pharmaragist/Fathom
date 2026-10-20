# Fathom Agent Guide (`AGENTS.md`)

This guide serves as the definitive reference for AI agents working on Fathom—a high-performance, modular Flutter music player. It details the complete architecture, data flow, state management contracts, DSP audio pipeline, and UI view hierarchies.

Section 7 (`Known Gaps`) lists every place the code currently disagrees with this document. Treat section 7 as the work queue: those are code defects to fix, not contracts to copy.

---

## 1. Directory Structure & File Taxonomy

```text
lib/
├── main.dart                      // Entry point: Bootstrap, system UI, root providers. Exports FathomApp
├── content.dart                   // RootShell: multi-page shell, shared chrome, page stack, toast layer, dismiss layer, BottomPanel overlay
├── models/
│   ├── tracks.dart                // Domain model: FathomTrack & TrackOrigin
│   └── ytmusic.dart               // YtItem: one remote result + parseYtDuration
├── common/
│   ├── colors.dart                // FathomPalette (material_color_utilities tones) + FathomColors token getters, accent swatches
│   ├── constants.dart             // App metadata, EQ band tables, speed presets, FathomRepeatMode, formatters
│   ├── settings.dart              // FathomSettings: unified enum-based key-value preferences store
│   ├── search.dart                // FathomSearch: the rail's single query, shared by every surface
│   ├── toasts.dart                // FathomToasts: the shell's in-memory transient message queue
│   ├── library.dart               // FathomLibrary: storage permission handling, media querying, art caching
│   └── player.dart                // FathomPlayer: just_audio engine, queue management, palette extraction
├── services/
│   ├── audio.dart                 // FathomAudioSession & FathomAudioHandler (audio_service lockscreen controls)
│   ├── equalizer.dart             // FathomNativeEqualizer: MethodChannel bridge to the native ten band stage
│   ├── autoeq.dart                // FathomAutoEq: AutoEQ catalogue index and ten band result fetch/parse
│   ├── yt_source.dart             // FathomYtSource contract + FathomYtMusic, the remote source
│   ├── downloads.dart             // FathomDownloads: remote audio fetch, MediaStore filing, download manifest
│   ├── power.dart                 // FathomPowerState: Android Battery Saver state, reported live
│   └── artwork.dart               // FathomArtCache: remote artwork bytes, keyed by videoId
├── panels/
│   ├── bottom_panel.dart          // FloatingIslandPlayer: compact player island, Now Playing push
│   └── queue.dart                 // Drag-and-drop up-next queue drawer
├── pages/
│   ├── library.dart               // Track list with alphabet scrubbing, merged search results, sort modal
│   ├── equalizer.dart             // 10-band DSP equalizer, preset save/edit and AutoEQ import (shell destination)
│   ├── playing.dart               // Full-screen Now Playing view with three-cover carousel & volume control
│   └── settings.dart              // App settings interface (typography, accent swatches, gapless, data save)
└── components/                    // UI primitives, one widget family per file
    ├── art.dart                   // ArtThumb, RemoteArt, TrackArt and the trackArtBytes helper
    ├── shell_chrome.dart          // ShellChrome: the backdrop + header every shell page wears
    ├── page_header.dart           // PageHeader, shellTrailing, and the settings route builder
    ├── backdrop.dart              // AmbientBackdrop: top-aligned radial gradient shell layer
    ├── toast_layer.dart           // FathomToastLayer: glass message cards below the header
    ├── carousel.dart              // CoverCarousel: the sliding-card deck Now Playing swipes
    ├── glass.dart                 // GlassContainer & FlatContainer: the frosted and flat surface primitives
    ├── flat_icon_button.dart      // FlatIconButton: minimal icon button primitive
    ├── flat_slider.dart           // FlatSlider: minimal slider primitive
    ├── flat_switch.dart           // FlatSwitch: minimal switch primitive (settings, equalizer)
    ├── track_actions.dart         // showTrackActions: per-track menu (play, play next, queue, download)
    ├── nav_rail.dart              // FloatingNavRail: bottom navigation rail
    └── styled_list_view.dart      // StyledListView: shared list & scaffolding primitive
```

> **Import Rule**: Always use direct relative imports (e.g., `import '../common/player.dart';`). Barrel files and shared-global modules are strictly prohibited — they cause circular dependencies and dead code bloat. Cross-widget state belongs on a notifier owned by the shell or a service; the former `lib/common/states.dart` globals were removed for this reason.

### Platform Configuration

`android/app/src/main/AndroidManifest.xml` declares the audio platform surface. Permissions are deliberate; adding one requires a documentation update here.

| Permission | Reason |
| --- | --- |
| `INTERNET` | AutoEQ catalogue downloads from the equalizer page; remote search, streaming and downloads |
| `READ_MEDIA_AUDIO` | Media store query on Android 13+ |
| `READ_EXTERNAL_STORAGE` (`maxSdkVersion="32"`) | Media store query below Android 13 |
| `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`) | Filing a download into the shared Music folder below API 29; requested on demand, never at startup |
| `ACCESS_MEDIA_LOCATION` | Artwork metadata access |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | `audio_service` playback service |
| `WAKE_LOCK` | Playback continues with screen off |
| `POST_NOTIFICATIONS` | Playback notification controls |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevents playback service being killed |
| `MODIFY_AUDIO_SETTINGS` | `AndroidEqualizer` DSP pipeline |
| `BLUETOOTH_CONNECT`, `BLUETOOTH` (`maxSdkVersion="30"`) | Bluetooth media controls |

* **Application ID / namespace**: `pharmaracist.fathom`.
* **Notification channel ID**: `pharmaracist.fathom.playback` (`player.dart`, `AudioServiceConfig`).
* **Method channels**: all three are registered by hand in `MainActivity.configureFlutterEngine`, not through a plugin registrant. `pharmaracist.fathom/equalizer` (`FathomEqualizerPlugin`), `pharmaracist.fathom/downloads` (`FathomDownloadsPlugin`), and `pharmaracist.fathom/power` (`FathomPowerPlugin`) — the downloads plugin is constructed with the activity because filing a download below API 29 may have to ask for storage access, and `MainActivity.onRequestPermissionsResult` forwards the answer to it so a held call is never leaked. The power plugin is constructed with the activity too (it needs a `Context` for `PowerManager`), and is handed its `MethodChannel` so the `ACTION_POWER_SAVE_MODE_CHANGED` receiver it registers while started can report back; `MainActivity.cleanUpFlutterEngine` calls its `release()` so an engine teardown never leaves that receiver registered.
* **`android:label`**: `Fathom`, matching `kAppName`.
* **Launcher icon pipeline**: `flutter_launcher_icons` config lives in `pubspec.yaml`; never hand-edit the generated files under `android/app/src/main/res`. Vector source is `assets/branding/icons/fg.svg` (tabler `wave-sine`, stroke forced to `#FFFFFF`); rasterize it to `assets/branding/icons/fg.png` at 1024x1024 (e.g. `magick -background none -density 4096 fg.svg fg.png`) and reuse that PNG as both `adaptive_icon_foreground` and `adaptive_icon_monochrome`. The pre-API 26 fallback is `assets/branding/icons/icon_fallback.png` (black iOS-style superellipse with the white emblem, built by `python3 tool/gen_fallback_icon.py`, requires Pillow) and is wired as `image_path`. `tool/gen_readme_layers.py` builds `assets/branding/icons/readme_layers.png`, the layer strip shown in `README.md`. The adaptive icon is defined in `mipmap-anydpi-v26/ic_launcher.xml` with `@color/ic_launcher_background` (`#000000`, from `values/colors.xml`) plus `@drawable/ic_launcher_foreground` and `@drawable/ic_launcher_monochrome` layers at `adaptive_icon_foreground_inset` (28%) inset; the monochrome layer is what Android 13+ themed icons tint with wallpaper colors. After changing any source image, regenerate with `python3 tool/gen_fallback_icon.py && dart run flutter_launcher_icons`.
* The manifest also registers `com.ryanheise.audioservice.AudioService` (foreground type `mediaPlayback`) and `MediaButtonReceiver`, both required by `audio_service`.

---

## 2. Core Domain Models

### `FathomTrack` (`lib/models/tracks.dart`)

Immutable model representing one playable item, from either origin.

```dart
enum TrackOrigin { device, ytMusic }

@immutable
class FathomTrack {
  final int id;              // Media store id, or the videoId hash for remote tracks
  final String title;        // Track title (defaults to "Untitled")
  final String artist;       // Artist name (defaults to "Unknown Artist")
  final String uri;          // File content URI; empty for remote tracks
  final TrackOrigin origin;  // Where the audio lives
  final String? videoId;     // Set for remote tracks; identifies the item everywhere
  final Uri? thumbUri;       // Remote thumbnail; device tracks read art from the media store
  final int? durationMs;     // Duration in milliseconds
  final int? dateAdded;      // Unix timestamp of file creation/addition
}
```

* **Equality**: `origin` plus the origin's own identity — `id` for device tracks, `videoId` for remote ones. A bare `id` comparison is wrong for remote tracks, whose ids are hashes.
* **Factories**: `FathomTrack.fromDevice(song)` parses raw `on_audio_query` objects. `FathomTrack.yt(item)` builds a remote track from a `YtItem`; its `uri` is empty on purpose, because remote audio addresses expire and are resolved at play time (section 3.3). Remote durations arrive as `"3:32"` and are converted to milliseconds via `parseYtDuration` (`lib/models/ytmusic.dart`).

---

## 3. State Architecture & Service Contracts

State is driven by `Provider` / `ChangeNotifier` and divided into five domains: `FathomSettings`, `FathomLibrary`, `FathomPlayer`, `FathomSearch` and `FathomDownloads`. The first three are long lived and notified; `FathomSearch` is a small in-memory holder with no persistence; `FathomDownloads` owns the download manifest and the in-flight fetches.

### 3.1 `FathomSettings` (`lib/common/settings.dart`)

Unified, strongly typed settings store backed by `SharedPreferences`.

#### The `SettingKey` Enum API

```dart
enum SettingKey {
  accentIndex('fathom.accent', 0),
  useArtAccent('fathom.art_accent', false),
  fontKey('fathom.font', 'Oswald'),   // the bundled family; 'System' opts back out
  gapless('fathom.gapless', true),
  speedIndex('fathom.speed', 1),
  sortIndex('fathom.sort', 0),
  eqEnabled('fathom.eq.enabled', true),
  eqPreset('fathom.eq.preset', null),
  shuffle('fathom.shuffle', false),
  repeatIndex('fathom.repeat', 0),
  dataSave('fathom.data_save', false), // Smaller remote thumbnails, fewer rows and results
  lowEnd('fathom.low_end', false),     // Flat cards instead of frosted glass (see section 5). The user's stored choice only; power save overrides it at read time
  themeIndex('fathom.theme', 2);       // 0 = Light, 1 = Dark, 2 = Auto (follow the device)
}
```

* **Accessors**:
  * `T get<T>(SettingKey key)`: returns the stored value, or the key's `defaultValue` when unset.
  * `void set<T>(SettingKey key, T value)`: updates memory, persists to disk when `prefKey` is non-empty, and calls `notifyListeners()` **only when the value actually changed**. Callers must not rely on `set` to emit when writing an identical value.
* **Derived read-only accessors**: `accent`, `repeatMode`, `themeMode` and `lowEndInForce` are the sanctioned exceptions to the "no custom getters" rule in section 6.1. They encapsulate the index↔enum and index↔swatch mapping, nothing else. `themeMode` maps `themeIndex` (0/1/2) onto `ThemeMode.light`/`dark`/`system` with an explicit switch; the `ThemeMode` enum's own order does not match the indices. `lowEndInForce({powerSave})` returns `low_end` OR `powerSave`, and is the one answer to "is low-end mode actually in force" — it takes the battery state as a parameter rather than depending on the native power service, because that state is not a preference and `FathomSettings` must not grow a mutable field for it. The stored `low_end` key is never written while power save is on. Do not add further getters with mutation or caching side effects.
* **Dynamic accent resolution**: `settings.accent` returns the `PaletteGenerator`-extracted artwork accent while `useArtAccent == true` and an extracted color exists; otherwise it falls back to `FathomColors.accentSwatches[accentIndex]`.
* **EQ gain staging**: gains are stored out-of-band in `_eqGains` (persisted under `fathom.eq.gains` as `hz#db` pairs). `stageEqGain(hz, db)` mutates the live map for immediate DSP feedback; `commitEq()` persists. `eqGains` returns an unmodifiable view.
* **EQ preamp**: the input gain applied before the band filters is `_eqPreamp`, staged by `stageEqPreamp(db)`, persisted under `fathom.eq.preamp`, and read back as `eqPreamp`. It only reaches DSP on the native (`DynamicsProcessing`) path.
* **EQ presets**: named curves are persisted under `fathom.eq.presets` as JSON `{"<name>": {"gains": [10 values], "preamp": db, "source": "<wire>"}}`, and the store never holds a name that collides with a built-in (`kEqPresets`). `EqPreset` is source-tagged: `EqPresetSource.user` for curves saved on the equalizer page, `EqPresetSource.autoEq` for curves imported from the AutoEQ catalogue. Both kinds go through the same `saveEqPreset(name, preset)` / `applyEqPreset(name)` path, and `eqPresetNames(source)` lets a surface render one source at a time: the equalizer chip row lists built-ins, then `user`, then `autoEq`. Presets are always `kEq10Bands` order plus a preamp, so an importer must map its curve onto those ten bands. The AutoEQ importer (`FathomAutoEq`) does exactly that: it downloads `FixedBandEQ.txt`, whose ten filters already match `kEq10Bands`, and rejects any document whose filter count or centre frequencies do not line up. Gains are clamped to `FathomNativeEqualizer.minDecibels`/`maxDecibels` and the preamp to `maxPreampDecibels`; when a document omits its own `Preamp:` the peak gain is cancelled instead.

### 3.2 `FathomSearch` (`lib/common/search.dart`)

Holds the one search field's state. There is a single query because there is a
single field; a search is expected to reach both collections at once.

* `query` is the `ValueNotifier<String>` behind the rail's text box. It survives a route push, so returning from Now Playing restores what was typed.
* `clear()` empties it, which is what "show everything" means on the library page.
* Nothing binds a query to a source. The library page reads `query` and decides what a match means: device tracks by title and artist, remote results by asking the source. Do not reintroduce a per-source query or an "active source" concept; the field is the whole surface.

### 3.3 `FathomLibrary` (`lib/common/library.dart`)

Manages system audio storage access, background scanning, and image memory caching.

* **Lifecycle awareness**: uses `AppLifecycleListener` to refresh the media list when returning from background.
* **Status pipeline**: `FathomLibraryStatus` transitions `idle` -> `permissionNeeded` / `loading` -> `ready` / `failure`.
* **Artwork cache**: `Future<Uint8List?> artFor(int id)` is the single owner of cached album artwork bytes. It eliminates scroll stutter in lists; no other component may keep a parallel artwork cache (Known Gaps 7).
* **Artwork URI**: `Uri? artUriForTrack(FathomTrack track)` resolves the artwork content URI used by `ArtThumb` and the backdrop.

### 3.4 `FathomPlayer` (`lib/common/player.dart`)

Central audio engine linking `just_audio`, hardware DSP effects, `audio_service`, and dynamic color extraction.

* **Audio pipeline**: initializes `AudioPlayer` with an `AndroidEqualizer` attached via `AudioPipeline(androidAudioEffects: [...])`.
* **Remote resolution**: the player owns the `FathomYtSource` it was constructed with. `_resolveAll(tracks)` turns a list into playable `AudioSource`s in one batch call, remembering each remote address under `_resolvedYt` (`videoId` -> `Uri`) for as long as the queue holds it. A track whose address cannot be resolved is dropped from the queue rather than left as a silent entry, because just_audio's sources and `_sourceQueue` must stay index-aligned.
* **Queue operations**:
  * `playFrom(List<FathomTrack> list, int index)`: replaces the engine queue using `AudioPlayer.setAudioSources(List<AudioSource>)` where each entry is `AudioSource.uri(uri, tag: track.id)`, then applies shuffle and loop mode and starts playback. `ConcatenatingAudioSource` is the legacy mechanism and must not be reintroduced.
  * `enqueue(tracks)` and `playNext(tracks)` append after the current item or after the current one respectively; both fall back to `playFrom` when nothing is playing.
  * `moveAt(int from, int to)` and `removeAt(int index)`: reorder and remove entries, then call `_rebuildSources()`, which replays the queue into the engine at the same index, position and playing state. just_audio holds its own copy of the sources, so no structural edit may skip this step.
* **List order is not play order.** `_sourceQueue` is the editable list the queue panel edits, index-aligned with the engine's sources. Shuffle never rewrites it: just_audio keeps its own shuffled permutation, so what plays next is `queue[_selectedIndex + 1]` only when shuffle is off. Everything that has to answer "what comes next" therefore asks the engine, never the list:
  * `nextTrack` / `previousTrack` are the neighbour a skip would land on, in play order, or `null` when the skip is blocked. The Now Playing carousel is handed these rather than computing an index, which is what keeps its side covers correct with shuffle on.
  * `canSkipNext` / `canSkipPrevious` compare `AudioPlayer.nextIndex` / `previousIndex` against the current index. They are not a repeat-mode switch: repeat-one and a single-item queue both resolve to "next" == "now", and a shuffled order can have a next track at the end of the list or none at the start of it.
* **Media item ownership**: `_pushMediaItem()` publishes the `MediaItem` for the current track to `FathomAudioHandler`; `playFrom`, `playIndex`, `moveAt`, and `removeAt` all call it. A remote track has no uri yet, so its media identity is `yt:<videoId>` and its art is the remote thumbnail.
* **Palette extraction**: on track change, when `useArtAccent == true`, `_extractArt(track)` samples dominant vibrant colors from `trackArtBytes(library, track)` — device artwork or the cached remote thumbnail — and calls `settings.updateArtAccent(color)`.

### 3.5 `FathomDownloads` (`lib/services/downloads.dart`)

Fetches a remote track's audio and files it on the device. Built in `main` rather than by the provider tree, because it has to rescan the library the moment a file lands — it is given the player's `FathomYtSource` and an `onFinished` callback, and it never learns what a library is.

* **The chain**: resolve an address from the source, stream the bytes into the app's own temp directory, sniff the container from the first bytes, then hand the finished file to Android, which writes it into the shared Music collection. Nothing durable is stored on the way in, because those addresses expire.
* **The manifest** is a `videoId` -> MediaStore row map under `downloads.manifest.v1`. It answers two questions and nothing else: "has this remote track already been fetched" and "is this device track one of ours". Losing it costs re-downloading, never correctness — the files are already in the media store.
* **Concurrency**: `maxConcurrent` is 3. Beyond that a track waits as `DownloadState.pending`; the future returned by `download()` completes when the work actually finishes, even if it queued, so a caller can await a real outcome.
* **States**: `download(track)` returns false without side effects when there is nothing to do (no remote id, already in the manifest). Otherwise it moves `idle` -> `pending`/`running` -> `done` or `failed`, and `stateOf` / `progressOf` are the read surface a menu needs. A failed track can be retried; a running or pending one cannot be started twice.
* **Rescan**: the manifest is persisted before `onFinished` fires, so the library scan that follows sees a file whose row id is already recorded, and the badge is correct on the first rebuild.

---

## 4. Audio Pipeline & OS Services (`lib/services/`)

* **`FathomAudioSession`**: configures hardware output via `AudioSession.instance` set to `AudioSessionConfiguration.music()`.
* **`FathomAudioHandler`**: subclasses `BaseAudioHandler` to interface with native OS playback services (Android MediaSession / iOS Remote Command Center).
  * `sync()` maps `just_audio` state onto an OS-level `PlaybackState`: control buttons (`skipToPrevious` / `play` / `pause` / `skipToNext`, gated by `FathomPlayer.canSkipNext` / `canSkipPrevious`), seek system actions, `playing`, `processingState`, `updatePosition`, `bufferedPosition`, `speed`, and `queueIndex`. `sync()` does **not** publish `MediaItem`; that belongs to `FathomPlayer._pushMediaItem()`.
  * Handles lock screen events: `play`, `pause`, `stop`, `skipToNext`, `skipToPrevious`, `seek`, `fastForward`, `rewind`.
* **`FathomNativeEqualizer`** (`lib/services/equalizer.dart`): `MethodChannel('pharmaracist.fathom/equalizer')` bridge to the native ten band stage. Every call is failure tolerant; when `isSupported()` reports false the player keeps the hardware bands. Owns the gain and preamp ranges (`minDecibels`, `maxDecibels`, `maxPreampDecibels`).
* **`FathomPowerState`** (`lib/services/power.dart`): `MethodChannel('pharmaracist.fathom/power')` bridge to Android's Battery Saver. Built and `start()`ed in `main` beside the other services, and provided so surfaces can read it. It is a `ChangeNotifier` rather than a `ValueListenable<bool>` because its subscribers are unequal: `FathomApp` needs to rebuild the whole subtree (it owns the one write of `GlassContainer.blurEnabled`), while the settings row only needs a flag it can `select`. `start()` reads `isPowerSave` once and subscribes to `onPowerSaveChanged`; `stop()` unsubscribes and the native side unregisters its receiver, so nothing is left registered. Every call is failure tolerant and every failure means "not saving power", so a missing or broken bridge can never wedge the app in low-end mode.
* **`FathomYtSource`** (`lib/services/yt_source.dart`): the remote music source, hidden behind an interface so the rest of Fathom never names the package that provides it. `FathomYtMusic` is the only implementation.
  * `initialize()` starts the backend once and remembers the outcome; `retry()` clears that memo for the error panel's retry action. `isReady` and `error` describe a failed start instead of throwing at callers.
  * `search(query, limit: quality:)` is a stream that yields progressively; `quality` is `YtQuality.low` or `high` and maps to the thumbnail size the backend fetches. The library page owns supersession: it bumps a token per keystroke and drops results carrying an older one, because the stream itself has no notion of a cancelled search.
  * `audioUri(videoId)` and `audioUris(ids)` resolve addresses at play time. The rule is absolute: no `FathomTrack` ever stores an audio address, because they expire.
  * The market is derived from the device locale (`FathomYtMusic.deviceCountry`) rather than a setting.
* **`FathomArtCache`** (`lib/services/artwork.dart`): remote artwork bytes keyed by `videoId`, not by the thumbnail URL, because the URL is a rewrite that changes with the requested quality while the item stays the same. Concurrent callers for one item share a single request. Failures return null so a missing thumbnail can never break a row or a playback start.
* **`FathomAutoEq`** (`lib/services/autoeq.dart`): read-only client for the public AutoEQ catalogue, reachable as the `FathomAutoEq.instance` singleton. `entries()` downloads and caches the recommended-results index for the process lifetime; `fetch(entry)` downloads one `FixedBandEQ.txt` and maps it onto `kEq10Bands`, returning a source-tagged `EqPreset`. Failures surface as `AutoEqException` with a message safe to display; the equalizer page's `Get` chip keeps its panel open so the user can retry.

---

## 5. UI Layer & Component Hierarchy

### Shell Structure (`lib/content.dart`)

`RootShell` is a **multi-page shell**: `ShellPage` (`enum ShellPage { library, equalizer }`, carrying each destination's header title) is the one source of truth for what is on screen, held in a `ValueNotifier` that the rail reads and the shell switches on. Pages are *not* pushed routes — the equalizer is a destination, switched by the rail — so the shell renders a layered `Stack`:

1. **`ShellChrome`** (`lib/components/shell_chrome.dart`): the fixed chrome every page wears — the `AmbientBackdrop` behind and the `PageHeader` above. It is built once, *outside* the page switch, so a page change never cross-fades or duplicates the backdrop or the header. It owns the canonical header padding (`20` gutters, `viewPadding.top + 8` top, `14` below); `PageHeader` carries no padding of its own, and a page that added its own would drift from its neighbours. The header's title and trailing controls are derived from `ShellPage`, so they change in place while the body alone changes.
2. **`PageView`**: both destinations mounted, side by side, moved by rail tap or horizontal swipe. See *Page Swipe* below.
3. **`FathomToastLayer`** (`lib/components/toast_layer.dart`): the message surface, wrapped in an `IgnorePointer` because a toast is information and must never take a tap meant for the list.
4. **Dismiss layer**: a `Positioned.fill` that sits *below* `BottomPanel`, gated on the search field being focused. Tapping outside closes the keyboard. It must stay under the panel so the panel's own controls stay live, and it must stay a separate layer from the page so the text-selection toolbar — which lives in the root overlay above routes — is never swallowed by it.
5. **`BottomPanel`** (`lib/panels/bottom_panel.dart`): combines `FloatingIslandPlayer` (compact mini-player with horizontal swipe-to-skip gestures) and `FloatingNavRail` (`lib/components/nav_rail.dart`). The rail carries one search field, bound to `FathomSearch.query`, and is the single way between destinations.

### Page Swipe (`PageView` + `_KeepAlive`)

The shell body is a `PageView` over `ShellPage.values`, so its `index` **is** the page and there is no second index to keep in step. Both ways to change destination move the same thing:

* A **rail tap** calls `_runTransition`, which writes `_page` and then `animateToPage`s the view, locking nav taps until it settles (`_animating`) so a second tap cannot queue a scroll behind an in-flight one.
* A **swipe** is adopted by the controller listener (`_onPageSettled`) once the view has come to rest, using `page.round()` — so a drag pulled back to its origin leaves the destination alone.

Both paths unfocus first, which is what collapses an open search; a page change must never strand the search field and its dismiss layer.

Both destinations stay **mounted**. The library is the expensive one — it owns a scroll controller, memoised sorted lists and a running remote search — and tearing it down to rebuild on the way back costs a full rescan and loses all of that, so every page is wrapped in `_KeepAlive` (`AutomaticKeepAliveClientMixin`), which is how a `PageView` page opts out of being disposed once it scrolls away. Neither the backdrop nor the header is inside the view, so they never move with a swipe.

Horizontal drags inside a page (`SingleChildScrollView`s, chip rows) still win their own gestures: Flutter resolves the axis conflict in the inner scrollable's favour, and only an over-scroll at its edge reaches the view.

### Glass Surfaces (`lib/components/glass.dart`)

The file holds a two-member family: `GlassContainer`, the floating-surface primitive (bottom panel, sheets, the toast layer, the action sheet, the scrubber label), and `FlatContainer`, the panel primitive for cards that sit *behind* opaque content inside a page (the settings sections, the equalizer cards, the library status block). Picking between them is the one rule here:

* **Floating over live content the user can still see around and through it** (a sheet over the page, the mini player over the list, a toast, an inline label above a row) ⇒ `GlassContainer`. The blur is what makes the card read as a separate layer.
* **Sitting behind opaque content inside a page** (a list of rows, a row of labels and chips, a status panel) ⇒ `FlatContainer`. The content covers the pixels behind the card entirely, so sampling them costs a `saveLayer` and shows nothing.

`GlassContainer` has two rendering modes, chosen by `GlassContainer.blurEnabled`:

* **Glass** (default): `ClipRRect` > `BackdropFilter(blur)` > `AnimatedContainer`, the frosted look.
* **Flat**: `ClipRRect` > `AnimatedContainer`, no `BackdropFilter` anywhere in the subtree. This is `SettingKey.lowEnd`, "Low-end mode" in Settings > Appearance.

The mode is actually in force when `FathomSettings.lowEndInForce` says so: the stored preference, or forced on while Android's Battery Saver is active. Power save never writes the key — the override is derived at read time, so turning battery saver off restores the user's own choice. While it is on, the Settings row reads ON and is not tappable, with "On: battery saver" as its reason.

`FlatContainer` is deliberately **not** `GlassContainer` with a flag: it has no `BackdropFilter` in its subtree at all, so it can never pay for a `saveLayer` no matter what `blurEnabled` says. It carries no `blur` and no `bgOpacity` — a blur is meaningless on a surface that must not sample behind itself, and the flat fill is a fixed recipe rather than a caller-tuned opacity (the fill and its accent tint have to move together to stay a legible panel). Its public shape is `child`, `radius` (22), `accent`, `padding`, `shadow` and `borderOpacity` (0.07), the last of which means exactly what `GlassContainer.borderOpacity` means.

The flat look lives in **one** private helper, `_flatDecoration`, called by both `GlassContainer`'s flat branch and `FlatContainer`, so the two surfaces cannot drift. A flat card has no blurred sample to separate it from what is behind it, so its fill carries that separation itself — an accent tint (0.18 dark / 0.14 light) over a partially-opaque background (0.72 dark / 0.86 light), with the denser fill in the light theme, which has almost no luminance to separate with — and the 1px border, from `baseOutline` (accent blended into `onSurface`, else plain `onSurface`) at the caller's opacity raised ~1.8x and clamped in light, is what defines its edge. Both surfaces animate the decoration with an `AnimatedContainer` over 150ms, so an accent change animates.

The blur and flat modes of `GlassContainer` must stay **structurally different subtrees**, not one tree with a `sigma` of zero: a `BackdropFilter` costs a `saveLayer` even at zero sigma, so leaving one in the flat path would defeat the setting entirely.

`blurEnabled` is a plain `static`, deliberately: a notifier would rebuild every card on a write and a constructor parameter would have to be threaded through every call site. The cost of that choice is that **writing it does not repaint anything by itself**. It is written in exactly one place — `FathomApp.build`, from `settings.lowEndInForce(powerSave: widget.power.isPowerSave)`, next to `FathomColors.updateBrightness` — which works only because that widget rebuilds from both of its sources: the settings listener and the `FathomPowerState` listener, since a power save change has to repaint the app just as a setting change does. Any new global of this kind must follow the same pattern: write it from an already-rebuilding ancestor and document the read site. `FlatContainer` never reads it.

### Page Header (`lib/components/page_header.dart`)

`PageHeader(title, trailing)` is the row itself; `ShellChrome` places it. The library destination passes `shellTrailing(context)`: the settings gear and a rescan icon button. Pages must not re-implement those controls, and the equalizer destination has no back control — the rail is the one way between destinations. `utilityRoute` is the single right-sliding transition Settings uses, and `settingsRoute` is the builder on top of it.

### Message Surface (`lib/common/toasts.dart`, `lib/components/toast_layer.dart`)

Toasts are the app's only transient message surface; do **not** use `SnackBar`. The bottom edge belongs to the mini player and the nav rail, so a message there would cover the controls it is usually reporting about. `FathomToasts` is a small in-memory queue provided in `main` (above the shell, so a message survives a page switch); `FathomToastLayer` renders it as glass cards directly below the header, newest nearest the header. Each toast has an `icon`, a `ToastTone` (`neutral` / `success` / `failure`) driving its accent, and an auto-dismiss `duration`. A long-running message (a download in flight) is shown with a long duration and dismissed explicitly when its outcome is known. Read the notifier from `context` *before* an await — the page that raised the message may be gone by the time the work finishes.

### Search Surfaces

`LibraryPage` is the search surface. With no query it shows the whole library sorted; with one it shows device matches first and remote results after them, under two section headers (`StyledListView.sectionFor`). Remote results are debounced against `FathomSearch.query`, streamed progressively, and skip anything already in the download manifest — that track is a device track now, so it belongs in the first section. There are no suggestions and no browsing.

### Hero Transition Pattern

Tapping the mini-player pill or a track tile in `LibraryPage` pushes `NowPlayingPage` through a custom `PageRouteBuilder` using `Curves.easeInOutCubic`. There must be exactly one shared route builder for this transition; the cover art morphs across screens using the Hero tag format:

```dart
tag: 'fathom-art-${track.id}'
```

Only the *current* cover carries the tag. The carousel beside it (`_CoverCarousel`) builds exactly three cards — previous, current, next — and swipes drive `skipNext` / `skipPrevious` rather than a page index. A `PageView` over the whole queue would carry a second index that has to stay in step with the player's, and the two disagree the moment shuffle or a queue edit moves the current track; do not reintroduce one. The neighbour covers are handed in from `FathomPlayer.nextTrack` / `previousTrack`, so they follow the engine's shuffled play order — never derive them as `queue[selectedIndex ± 1]`.

---

## 6. Development Conventions for Agents

1. **State mutation**: reach settings exclusively through `settings.get<T>(SettingKey)` / `settings.set<T>(SettingKey, value)`. Do not add new mutable getters or setters to `FathomSettings`. Read-only derived getters are permitted only for documented key mappings (`accent`, `repeatMode`, `eqGains`, `lowEndInForce`) and must have no mutation or caching side effects.
2. **Re-renders**: prefer `context.select<T, R>()` over `context.watch<T>()` in lists and high-frequency widgets; if a widget reads a single field from a notifier, use `select` for that field.
3. **Theming**: derive surfaces, dividers, and text styles from `FathomColors` (`lib/common/colors.dart`) and `Theme.of(context).colorScheme`. Never inline a literal `Color(0x...)` in a widget. The app is theme-aware (light, dark, and auto-follow-device, chosen by `SettingKey.themeIndex`): `FathomColors` tokens resolve against the active `FathomPalette` — one generated-material palette per brightness, built from the seed `0xFFDC8666` via `Hct`/`TonalPalette` — which `FathomApp` re-points before the subtree builds. Read colors from the tokens, never from a literal and never from a hard-coded white/black; the Now Playing screen is the one exception and uses the theme-independent media tier (`onMedia`, `mediaScrim`, `mediaBackground`).
4. **Imports**: direct relative imports only, one component family per file. No barrel files, no shared-global modules.
5. **Platform surface**: declare a new Android permission only together with its row in section 1, and keep the manifest `android:label`, application ID, and notification channel ID consistent with section 1.
6. **Global render switches**: a process-wide rendering choice that every widget must read during build (there is exactly one: `GlassContainer.blurEnabled`) is a `static` written from `FathomApp.build` next to `FathomColors.updateBrightness`, and read at the widget. It is *not* a notifier — that would rebuild every reader on a write — and *not* a threaded parameter, which would have to reach every call site. Such a static does not repaint on assignment, so the writer must be a widget that already rebuilds when the setting changes. Document the write site and the reason on the field itself; do not add a second writer, and do not introduce a second global of this kind without the same justification.

---

## 7. Known Gaps (code must be fixed to match this document)

1. ~~Hardcoded surfaces bypass `FathomColors`.~~ Closed. Every `Color(0x..)` outside `common/colors.dart` was retired into palette tokens; `GlassContainer.surface` and the switch's off-state constants are gone, and `material_color_utilities` 0.13 renamed `TonalPalette.fromHueAndChroma` to `TonalPalette.of` and `tone()` to `get()` — that rename is done, so a version bump past 0.13 needs no further edits here.
2. ~~**`Colors.white` / `Colors.black` are still used as foregrounds** in ~116 places (list tiles, sheets, the media tier).~~ Closed. The sweep is done: surface/list/sheet foregrounds are `onSurface` alpha tiers, modal barriers are `scrim`, Now Playing uses the chroma-free media tier (`onMedia*`, `mediaBackground`, `mediaScrim`), ink on accent fills is `FathomColors.onAccent(accent)`, and the last `Colors.white`/`Colors.black`/`Color(0x..)` outside `common/colors.dart` is gone (`Colors.transparent` aside). New code must not reintroduce them.
3. **Remote artwork is memory-only.** `FathomArtCache` has no disk tier, so every session refetches thumbnails for remote items. Downloads landed beside it in `FathomDownloads`, which keeps the two concerns apart: a download is a finished file, a thumbnail is a cache.
4. **`QueuePanel` labels list order as "Up Next".** It renders `_sourceQueue`, which is the right thing to *edit* but is not the play order while shuffle is on, so the rows below the current track are not the tracks that will play. Showing play order instead makes drag-reorder ambiguous (a shuffled position does not name a list position), which is a design decision, not a transcription — do not change it silently.

## 8. Planned Work

* **Remote artwork disk tier.** Downloads are built; the remaining cache gap is thumbnails. `FathomArtCache` should grow a disk tier keyed the same way (`videoId`), consulted before the network, bounded by size rather than count, and never blocking a row's first paint.
* **Queue panel search and shuffle-by-drag** are unstarted and undesigned. Do not start either without a decision about what problem they solve.
