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
│   └── ytmusic.dart               // YtItem: one remote result
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
│   ├── yt_source.dart             // FathomYtSource contract + FathomYtMusic, the remote *fetcher* (no streaming)
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
| `INTERNET` | AutoEQ catalogue downloads from the equalizer page; remote search and track downloads |
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
* **Remote source dependency**: `newpipeextractor_dart` (NewPipe Extractor, native Kotlin, **GPL-3.0**). Fathom is private and undistributed, which is what makes the copyleft acceptable; publishing it would force Fathom to GPL-3.0. It replaced `yt_flutter_musicapi`, which shipped a Chaquopy CPython runtime plus `ytmusicapi`/`yt-dlp` inside the APK. Native Kotlin is why the swap also removed the Python runtime and the pub-cache patches. Android side requires: JitPack in `android/build.gradle.kts` (`allprojects.repositories`), and `isCoreLibraryDesugaringEnabled = true` plus `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` in `android/app/build.gradle.kts` (NewPipe targets Java 8 APIs the platform lacks below API 26). Its `flutter_inappwebview` dependency exists for the reCAPTCHA challenge only and is not wired into Fathom.

  **Rhino ships and is reachable — do not exclude it.** The extractor depends on `org.mozilla:rhino` and uses it to run YouTube's player JavaScript when a stream URL arrives as a `signatureCipher`: `VideoExtractor.getStream` goes through `YoutubeStreamExtractor`, which calls `YoutubeJavaScriptPlayerManager` to deobfuscate the signature through `JavaScript`, which is Rhino. Fathom never implements signature solving itself, but the extractor it delegates to still runs that path internally, so removing Rhino would replace a build-time warning with a `NoClassDefFoundError` on any track whose stream URL carries a cipher — an unexplained resolve failure on a subset of tracks. That is the failure shape this app works hardest to avoid.

* **R8 keep rules** (`android/app/proguard-rules.pro`): the Flutter Gradle plugin enables minification for **every** release build (`FlutterPlugin.kt` sets `releaseBuildType.isMinifyEnabled = true`), and it adds `proguard-android-optimize.txt`, its own `flutter_proguard_rules.pro`, and — purely by convention — this module's `android/app/proguard-rules.pro` when that file exists. So the file's *name* is load-bearing: it is picked up automatically and must not be renamed, and no `proguardFiles` call belongs in `build.gradle.kts`, because naming the files there would add the default rules a second time. The rules are `-dontwarn` rather than `-keep` because the classes they name are genuinely absent on Android: `JavaToJSONConverters` reflects over JavaBeans on a generic object-to-JSON path NewPipe never takes, and `RhinoScriptEngineFactory` exists only for JSR-223 service-loader discovery, which Fathom does not use. R8 cannot prove that unreachability, so the references are accepted. Regenerate the list from `build/app/outputs/mapping/release/missing_rules.txt` when a dependency changes.
* **`android:label`**: `Fathom`, matching `kAppName`.
* **Launcher icon pipeline**: `flutter_launcher_icons` config lives in `pubspec.yaml`; never hand-edit the generated files under `android/app/src/main/res`. Vector source is `assets/branding/icons/fg.svg` (tabler `wave-sine`, stroke forced to `#FFFFFF`); rasterize it to `assets/branding/icons/fg.png` at 1024x1024 (e.g. `magick -background none -density 4096 fg.svg fg.png`) and reuse that PNG as both `adaptive_icon_foreground` and `adaptive_icon_monochrome`. The pre-API 26 fallback is `assets/branding/icons/icon_fallback.png` (black iOS-style superellipse with the white emblem, built by `python3 tool/gen_fallback_icon.py`, requires Pillow) and is wired as `image_path`. `tool/gen_readme_layers.py` builds `assets/branding/icons/readme_layers.png`, the layer strip shown in `README.md`. The adaptive icon is defined in `mipmap-anydpi-v26/ic_launcher.xml` with `@color/ic_launcher_background` (`#000000`, from `values/colors.xml`) plus `@drawable/ic_launcher_foreground` and `@drawable/ic_launcher_monochrome` layers at `adaptive_icon_foreground_inset` (28%) inset; the monochrome layer is what Android 13+ themed icons tint with wallpaper colors. After changing any source image, regenerate with `python3 tool/gen_fallback_icon.py && dart run flutter_launcher_icons`.
* The manifest also registers `com.ryanheise.audioservice.AudioService` (foreground type `mediaPlayback`) and `MediaButtonReceiver`, both required by `audio_service`.

---

## 2. Core Domain Models

### `FathomTrack` (`lib/models/tracks.dart`)

Immutable model representing one item, from either origin. Only a device track is playable; a remote item must be downloaded first.

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
* **Factories**: `FathomTrack.fromDevice(song)` parses raw `on_audio_query` objects. `FathomTrack.yt(item)` builds a track from a `YtItem`: it is a *remote item*, not a playable track — `uri` is empty and stays empty, because no remote address is ever stored (they expire within hours) and nothing remote is streamed. It becomes playable only by being downloaded, at which point the library scan finds the file and it arrives as a device track. The extractor reports duration in whole seconds, so `durationMs` is that times 1000.

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
* **Playable means local.** The player holds no remote source and does not know YouTube exists. `_resolveAll(tracks)` turns a list into playable `AudioSource`s by taking only `TrackOrigin.device` entries; a remote item is dropped, because there is nothing to play until it has been downloaded and the library scan has found the file. Nothing is resolved lazily and no address is cached, so Fathom never depends on a stream URL still being valid — which is the whole point of being a fetcher-downloader rather than a streamer.
* **Queue operations**:
  * `playFrom(List<FathomTrack> list, int index)`: replaces the engine queue using `AudioPlayer.setAudioSources(List<AudioSource>)` where each entry is `AudioSource.uri(uri, tag: track.id)`, then applies shuffle and loop mode and starts playback. `ConcatenatingAudioSource` is the legacy mechanism and must not be reintroduced.
  * `enqueue(tracks)` and `playNext(tracks)` append after the current item or after the current one respectively; both fall back to `playFrom` when nothing is playing.
  * `moveAt(int from, int to)` and `removeAt(int index)`: reorder and remove entries, then call `_rebuildSources()`, which replays the queue into the engine at the same index, position and playing state. just_audio holds its own copy of the sources, so no structural edit may skip this step.
* **List order is not play order.** `_sourceQueue` is the editable list the queue panel edits, index-aligned with the engine's sources. Shuffle never rewrites it: just_audio keeps its own shuffled permutation, so what plays next is `queue[_selectedIndex + 1]` only when shuffle is off. Everything that has to answer "what comes next" therefore asks the engine, never the list:
  * `nextTrack` / `previousTrack` are the neighbour a skip would land on, in play order, or `null` when the skip is blocked. The Now Playing carousel is handed these rather than computing an index, which is what keeps its side covers correct with shuffle on.
  * `canSkipNext` / `canSkipPrevious` compare `AudioPlayer.nextIndex` / `previousIndex` against the current index. They are not a repeat-mode switch: repeat-one and a single-item queue both resolve to "next" == "now", and a shuffled order can have a next track at the end of the list or none at the start of it.
* **Media item ownership**: `_pushMediaItem()` publishes the `MediaItem` for the current track to `FathomAudioHandler`; `playFrom`, `playIndex`, `moveAt`, and `removeAt` all call it. Only device tracks are ever published, so the media item always has a real uri; downloaded tracks are ordinary device tracks by then and carry their own artwork.
* **Palette extraction**: on track change, when `useArtAccent == true`, `_extractArt(track)` samples dominant vibrant colors from `trackArtBytes(library, track)` — device artwork or the cached remote thumbnail — and calls `settings.updateArtAccent(color)`.

### 3.5 `FathomDownloads` (`lib/services/downloads.dart`)

Fetches a remote track's audio and files it on the device. Built in `main` rather than by the provider tree, because it has to rescan the library the moment a file lands — it is given a `FathomYtSource` of its own and an `onFinished` callback, and it never learns what a library is. It is the **only** holder of the remote source now: the player does not have one.

* **The chain**: resolve an address from the source, stream the bytes into the app's own temp directory, sniff the container from the first bytes, then hand the finished file to Android, which writes it into the shared Music collection. Nothing durable is stored on the way in, because those addresses expire.
* **The manifest** is a `videoId` -> MediaStore row map under `downloads.manifest.v1`. It answers two questions and nothing else: "has this remote track already been fetched" and "is this device track one of ours". Losing it costs re-downloading, never correctness — the files are already in the media store.
* **Concurrency**: `maxConcurrent` is 3. Beyond that a track waits as `DownloadState.pending`; the future returned by `download()` completes when the work actually finishes, even if it queued, so a caller can await a real outcome.
* **States**: `download(track)` returns false without side effects when there is nothing to do (no remote id, already in the manifest). Otherwise it moves `idle` -> `pending`/`running` -> `done` or `failed`, and `stateOf` / `progressOf` are the read surface a menu needs. A failed track can be retried; a running or pending one cannot be started twice.
* **The failure reason is a separate read from the bool result.** `failureOf(videoId)` returns why the last attempt failed, or null, and is cleared when the item is retried so it can never describe an attempt still in flight. It is deliberately not folded into `download`'s return value: a caller that only needs "did it work" should not have to carry a message, and the one that shows a message reads it here. This matters because the source resolves an address by returning null rather than throwing, so the reason is recorded in exactly one place and a caller that drops it turns every distinct cause — a captcha, a throttled request, a video with no audio stream — into the same "could not save".
* **Rescan**: the manifest is persisted before `onFinished` fires, so the library scan that follows sees a file whose row id is already recorded, and the badge is correct on the first rebuild.
* **Every step is bounded, and each bound is matched to what it actually covers.** A download has no natural end if a socket stalls halfway, so an unbounded chain leaves a row spinning forever and the message the user is waiting on never arrives. The three:
  * `resolveTimeout` (30s) covers the source handing back a media address. `_fetch` sets `connectionTimeout`, but that only governs the TCP connect, and resolving is a separate round trip it does not cover.
  * `transferTimeout` (10min) covers the whole audio transfer, not each chunk. A server can accept the connection and then stall mid-body, which hangs the per-chunk `await for`; a stalled transfer is indistinguishable from a slow one until it is bounded.
  * `remuxTimeout` (2min) covers the mp4 remux and tag — the one step with no socket underneath it, where a malformed input would otherwise leave FFmpeg reading for the rest of the run. On timeout the session is **cancelled** rather than abandoned, so the native process goes away too, and the untagged audio is returned instead: the tag is a nicety, and losing it must not lose the file.
  * `saveAudio` is deliberately **not** bounded. Below API 29 the native side holds the MethodChannel call while it asks for storage permission, so a timeout there would abort a legitimate user-facing dialog.

---

## 4. Audio Pipeline & OS Services (`lib/services/`)

* **`FathomAudioSession`**: configures hardware output via `AudioSession.instance` set to `AudioSessionConfiguration.music()`.
* **`FathomAudioHandler`**: subclasses `BaseAudioHandler` to interface with native OS playback services (Android MediaSession / iOS Remote Command Center).
  * `sync()` maps `just_audio` state onto an OS-level `PlaybackState`: control buttons (`skipToPrevious` / `play` / `pause` / `skipToNext`, gated by `FathomPlayer.canSkipNext` / `canSkipPrevious`), seek system actions, `playing`, `processingState`, `updatePosition`, `bufferedPosition`, `speed`, and `queueIndex`. `sync()` does **not** publish `MediaItem`; that belongs to `FathomPlayer._pushMediaItem()`.
  * Handles lock screen events: `play`, `pause`, `stop`, `skipToNext`, `skipToPrevious`, `seek`, `fastForward`, `rewind`.
* **`FathomNativeEqualizer`** (`lib/services/equalizer.dart`): `MethodChannel('pharmaracist.fathom/equalizer')` bridge to the native ten band stage. Every call is failure tolerant; when `isSupported()` reports false the player keeps the hardware bands. Owns the gain and preamp ranges (`minDecibels`, `maxDecibels`, `maxPreampDecibels`).
* **`FathomPowerState`** (`lib/services/power.dart`): `MethodChannel('pharmaracist.fathom/power')` bridge to Android's Battery Saver. Built and `start()`ed in `main` beside the other services, and provided so surfaces can read it. It is a `ChangeNotifier` rather than a `ValueListenable<bool>` because its subscribers are unequal: `FathomApp` needs to rebuild the whole subtree (it owns the one write of `GlassContainer.blurEnabled`), while the settings row only needs a flag it can `select`. `start()` reads `isPowerSave` once and subscribes to `onPowerSaveChanged`; `stop()` unsubscribes and the native side unregisters its receiver, so nothing is left registered. Every call is failure tolerant and every failure means "not saving power", so a missing or broken bridge can never wedge the app in low-end mode.
* **`FathomYtSource`** (`lib/services/yt_source.dart`): the remote music source, hidden behind an interface so the rest of Fathom never names the package that provides it. `FathomYtMusic` is the only implementation, and it is a **fetcher, not a streamer**: there is deliberately no "give me a URL I can play now" method, because a live stream address is the fragile half of every YouTube client — it expires, it is throttled, and keeping it valid is what forces signature deciphering.
  * `initialize()` prepares the extractor once and remembers the outcome; `retry()` clears that memo for the error panel's retry action. `isReady` and `error` describe a failed start instead of throwing at callers; `error` is about the *source*, not one fetch, so an unresolvable track never writes there — that would make one bad result look like the whole surface being down. The one piece of setup is `LocalizationExtractor.setLocalization(language, country)`; a wrong market still searches, so its failure is not fatal.
  * `search(query, limit: quality:)` returns a stream, but the extractor answers a whole page at once, so the stream is a shape callers already understand rather than a claim that results arrive one by one. `quality` is `YtQuality.low` or `high` and selects the smallest or largest thumbnail the item carries. The library page owns supersession: it bumps a token per keystroke and drops results carrying an older one.
  * `audioUri(videoId)` resolves one media address **at fetch time** for `FathomDownloads`, which downloads from it immediately. The rule is absolute: no `FathomTrack` ever stores an audio address, because they expire. An item whose address cannot be resolved returns null and is reported as a failed download, and `lastResolveError` carries why: a null answer is an ordinary outcome rather than a thrown one, so that field is the only place the cause survives, and a caller that drops it leaves the user with "Could not save" and nothing to act on.
  * The market is derived from the device locale (`FathomYtMusic.deviceCountry`, `deviceLanguage`) rather than a setting.
  * Failure modes are real and documented, not hypothetical: rate limiting, a reCAPTCHA challenge, and `FatalFailureException` when upstream YouTube changes. Search failing leaves playback of downloaded music working, which is why the fetcher is allowed to fail loudly at the search surface. Neither surface may swallow a cause in silence: the search stream's `onError` and the download failure path both have to carry it somewhere the user reads, because an empty state cannot distinguish "nothing matched" from "the search never ran", and a download toast cannot distinguish a captcha from a video that has no audio stream. One property of the native bridge bounds how precise those messages can be: the Kotlin extractor catches a failed audio-stream fetch into an *empty list* rather than an error, so a refusal to hand over a stream and a video with genuinely none are the same answer on the Dart side, and the wording says which of the two it can actually tell apart instead of inventing a finer distinction.
* **`FathomArtCache`** (`lib/services/artwork.dart`): remote artwork bytes keyed by `videoId`, not by the thumbnail URL, because the URL is a rewrite that changes with the requested quality while the item stays the same. Concurrent callers for one item share a single request. Failures return null so a missing thumbnail can never break a row or a playback start.
* **`FathomAutoEq`** (`lib/services/autoeq.dart`): read-only client for the public AutoEQ catalogue, reachable as the `FathomAutoEq.instance` singleton. `entries()` downloads and caches the recommended-results index for the process lifetime; `fetch(entry)` downloads one `FixedBandEQ.txt` and maps it onto `kEq10Bands`, returning a source-tagged `EqPreset`. Failures surface as `AutoEqException` with a message safe to display; the equalizer page's `Get` chip keeps its panel open so the user can retry.

---

## 5. UI Layer & Component Hierarchy

### Shell Structure (`lib/content.dart`)

`RootShell` is a **multi-page shell**: `ShellPage` (`enum ShellPage { library, equalizer }`, carrying each destination's header title) is the one source of truth for what is on screen, held in a `ValueNotifier` that the rail reads and the shell switches on. Pages are *not* pushed routes — the equalizer is a destination, switched by the rail — so the shell renders a layered `Stack`:

1. **`ShellChrome`** (`lib/components/shell_chrome.dart`): the fixed chrome every page wears — the `AmbientBackdrop` behind and the `PageHeader` above. It is built once, *outside* the page switch, so a page change never cross-fades or duplicates the backdrop or the header. It owns the canonical header padding (`20` gutters, `viewPadding.top + 8` top, `14` below); `PageHeader` carries no padding of its own, and a page that added its own would drift from its neighbours. The header's title and trailing controls are derived from `ShellPage`, so they change in place while the body alone changes.
2. **`PageView`**: both destinations mounted, side by side, moved by rail tap or horizontal swipe. See *Page Swipe* below.
3. **`FathomToastLayer`** (`lib/components/toast_layer.dart`): the message surface. It decides its own pointer behaviour rather than being wrapped in an `IgnorePointer` here: a toast is information and normally must not take a tap meant for the list, but a long-running card carries a close control that has to be reachable. Keeping that decision in one place is what stops the shell and the layer from disagreeing about it.
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

Toasts are the app's only transient message surface; do **not** use `SnackBar`. The bottom edge belongs to the mini player and the nav rail, so a message there would cover the controls it is usually reporting about. `FathomToasts` is a small in-memory queue provided in `main` (above the shell, so a message survives a page switch); `FathomToastLayer` renders it as glass cards directly below the header, newest nearest the header.

A toast carries **two lines of text, not one**. `title` is what happened and must survive; `detail` is the explanation, when there is one worth reading. The split exists because the two messages this surface carries are shaped differently: a confirmation is one short clause ("Saved"), while a failure is an outcome plus a cause ("Could not save" / "YouTube asked for a captcha"). Run together into a single clamped line, the half that gets truncated first is the half the user needed, so **never pass a cause through `title`** — a failure the user cannot act on is a failure reported twice.

The rest of the contract:

* `icon` and a `ToastTone` (`neutral` / `success` / `failure`) drive the glyph and accent; the tone supplies a default glyph when the caller names none, so an outcome is recognizable by shape before its words are read.
* `duration` is the auto-dismiss, defaulting to three seconds. A long-running message (a download in flight) is shown with a long duration and dismissed explicitly when its outcome is known.
* `dismissible` decides whether the card offers a close control. Off for an ordinary message, which the user has no reason to dismiss early and which would only gain a target to miss; **on for anything long-running**, because the alternative is a message the user cannot get rid of if the work outlives its usefulness. The layer lets taps through only when some visible card is dismissible, and only within the stack — an ordinary toast never swallows a tap meant for the page.
* Timers are tracked per id and cancelled by `dismiss`, `clear` and `dispose`. Do not reach for a loose `Future.delayed` here: clearing the queue would leave a callback scheduled against a message that is already gone.
* `maxVisible` caps the stack at three, dropping the oldest. A stack of glass cards stops being readable well before it stops fitting, and the newest is the one worth keeping.

The layer keeps its own `_Entry` list rather than reading the queue directly, because the notifier drops a toast the moment it is dismissed and a card that vanished between frames would never play its exit. A card enters by dropping in from the header and exits along the same path reversed; motion respects `MediaQuery.disableAnimationsOf`, which drops the travel and keeps a cross-fade.

Read the notifier from `context` *before* an await — the page that raised the message may be gone by the time the work finishes.

### Search Surfaces

`LibraryPage` is the search surface. With no query it shows the whole library sorted; with one it shows device matches first and remote results after them, under two section headers (`StyledListView.sectionFor`). Remote results are debounced against `FathomSearch.query`, checked against the download manifest — anything already fetched is a device track now and belongs in the first section — and **tapping one downloads it**; only a second tap, once the file is local, plays it. A remote row shows a download glyph in place of the play affordance and swaps it for a progress spinner while its fetch is in flight (`_fetch` guards against a second tap starting an overlapping fetch, which the download service would only refuse). The download's outcome is reported as a toast, and a failure carries the service's own reason rather than a generic phrase, because the causes are not interchangeable: a captcha is worth retrying later, a video with no audio stream never will be. A search that throws sets `_ytError` from the stream's error, so the empty-state panel says the search failed and why; leaving it unset would let the panel claim "No matches" for a search that never ran, which reads as a wrong answer instead of a failure. There are no suggestions and no browsing.

### Track List (`lib/components/styled_list_view.dart`)

`StyledListView<T>` is the app's scrolling list primitive, and it is the only thing that knows how a list meets the shell. It runs the full height of the page body — straight under the header, and behind the mini player and the rail — so both of its ends have to be handled deliberately rather than left to a hard boundary:

* **Both ends are faded, not cut.** `_EdgeFade` masks the scrolling rows with a linear alpha ramp via `ShaderMask` and `BlendMode.dstIn`, so a row scrolled to an end dissolves instead of being sliced flush by whatever it passes behind. `dstIn` multiplies the child's own alpha rather than replacing it, which matters because tiles animate in translucent — a tile mid-entrance fades from where it already is instead of being forced opaque first.
* **It is a shader, not a `ClipRRect`, and the difference is not cost.** Both cost a compositing layer, so a rounded clip would not save anything; it would anti-alias a curve and sever a row along a shape that has nothing to do with the row, leaving the translucent tiles behind it fighting the boundary. The ramp has no curved geometry and no boundary to disagree with. Do not "improve" this into a `ClipRRect`.
* **The falloff sits outside the list's own insets.** The ramp heights derive from `topInset`/`bottomInset`, so the first and last rows are not faded while they are still the things the eye is on. A viewport too short to hold both ramps (a keyboard, split screen) degenerates to no mask rather than hiding the middle of the list.
* **The mask covers the scrolling rows only.** The `_FastScrollbar` and its letter label live in the `Stack` above it, so scrubbing still overhangs the list as designed. Keep them outside the mask.
* **A tile cannot paint past its own box.** `TrackTile` is wrapped in a `ClipRect`, because the entrance animation scales to 96% and lifts 18px, and the playing indicator is positioned to the tile's edge. Without it those spill into neighbouring rows.
* **The scrollbar thumb's 56px floor yields to the track.** Clamping to a floor taller than the track itself puts `clamp`'s lower bound above its upper one, which throws and takes the whole list down. A viewport that short is reachable, so the floor is applied only when the track can hold it.

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
5. ~~**The ABI configuration conflict blocked every build.**~~ Closed. `splits { abi { ... } }` in `android/app/build.gradle.kts` collided with the Flutter Gradle plugin's own `ndk.abiFilters` injection, which AGP refuses ("Conflicting configuration ... in ndk abiFilters cannot be present when splits abi filters are set"). AGP raises this while creating variants, so it happens *during* configuration: no `afterEvaluate` can correct it, and the plugin's `disable-abi-filtering` opt-out cannot be set from `android/gradle.properties`, because it is read with `Project.findProperty` on `:app`, which never consults a properties file. The splits block was removed instead, so nothing conflicts and a plain build yields one APK that `flutter run` can install; `flutter build apk --split-per-abi` still produces split APKs on demand. Do not reintroduce a `splits` block without also solving the plugin's injection.
6. ~~**R8 failed the release build on reflective Rhino classes.**~~ Closed. `:app:minifyReleaseWithR8` reported six missing `java.beans`/`javax.script` classes, because the Flutter plugin enables minification for every release build and the module had no `android/app/proguard-rules.pro` for the plugin to pick up. The rules now exist. The build-time half is fixed; **the release build has not been run**, so R8's reachability analysis past the `-dontwarn` directives is unverified — see section 1 for why Rhino must stay.

## 8. Planned Work

* **Remote artwork disk tier.** Downloads are built; the remaining cache gap is thumbnails. `FathomArtCache` should grow a disk tier keyed the same way (`videoId`), consulted before the network, bounded by size rather than count, and never blocking a row's first paint.
* **Queue panel search and shuffle-by-drag** are unstarted and undesigned. Do not start either without a decision about what problem they solve.
* **reCAPTCHA navigator.** `newpipeextractor_dart` can hit a reCAPTCHA challenge, and it exposes a navigator hook for it that Fathom does not set, so that failure currently surfaces as a failed search. Wiring it would need the `flutter_inappwebview` dependency the package already pulls in, and a decision about whether a browser detour belongs in the app at all.
