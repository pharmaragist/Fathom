# Fathom Agent Guide (`AGENTS.md`)

Fathom: high-performance modular Flutter music player. This doc covers architecture, data flow, state contracts, DSP pipeline, UI hierarchy.

Section 7 (`Known Gaps`) lists every code/doc mismatch. Treat it as the work queue: defects to fix, not contracts to copy.

---

## 1. Directory Structure & File Taxonomy

```text
lib/
├── main.dart                      // Entry point: Bootstrap, system UI, root providers. Exports FathomApp
├── content.dart                   // RootShell: multi-page shell, shared chrome, page stack, dismiss layer, BottomPanel overlay
├── models/
│   ├── tracks.dart                // Domain model: FathomTrack & TrackOrigin
│   └── ytmusic.dart               // YtItem: one remote result, plus the shared thumbnail-selection helpers
├── common/
│   ├── colors.dart                // FathomPalette (monochrome material_color_utilities tones), FathomColors token getters, accent swatches
│   ├── constants.dart             // App metadata, EQ band tables, speed presets, FathomRepeatMode, formatters
│   ├── settings.dart              // FathomSettings: unified enum-based key-value preferences store
│   ├── search.dart                // FathomSearch: the rail's single query, shared by every surface
│   ├── selection.dart             // FathomSelection: in-memory device-track selection for batch delete
│   ├── library.dart               // FathomLibrary: storage permission handling, media querying, snapshot + art caching
│   ├── library_diff.dart          // Pure scan reconciliation: stable track keys, added/removed/moved/updated delta
│   ├── motion.dart                // FathomSpring, FathomMotion presets, FathomSpringCurve, SpringValue
│   └── player.dart                // FathomPlayer: just_audio engine, queue management, state restore
├── services/
│   ├── audio.dart                 // FathomAudioSession & FathomAudioHandler (audio_service lockscreen controls)
│   ├── equalizer.dart             // FathomNativeEqualizer: MethodChannel bridge to the native ten band stage
│   ├── autoeq.dart                // FathomAutoEq: AutoEQ catalogue index and ten band result fetch/parse
│   ├── yt_source.dart             // FathomYtSource contract + FathomYtMusic, the remote *fetcher* (no streaming)
│   ├── downloads.dart             // FathomDownloads: remote audio fetch, MediaStore filing, download manifest
│   ├── power.dart                 // FathomPowerState: Android Battery Saver state and battery-optimization exemption, reported live
│   ├── fonts.dart                 // FathomFonts: Google Fonts catalogue, on-demand TTF download and FontLoader registration
│   └── artwork.dart               // FathomArtCache: remote artwork bytes, keyed by videoId
├── panels/
│   ├── bottom_panel.dart          // FloatingIslandPlayer: compact player island, Now Playing push
│   └── queue.dart                 // Drag-and-drop up-next queue drawer
├── pages/
│   ├── onboarding.dart            // First-run walkthrough: feature tour, library/notification/battery permissions
│   ├── library.dart               // Track list with alphabet scrubbing, merged search results, sort modal
│   ├── equalizer.dart             // 10-band DSP equalizer as outline cards, preset save/edit and AutoEQ import
│   ├── downloads.dart             // What Fathom has fetched: files on the device, work in flight, failures
│   ├── playing.dart               // Full-screen Now Playing view with three-cover carousel & volume control
│   └── settings.dart              // App settings as sticky outline sections (typography, fonts, accents, AMOLED, gapless, data save)
└── components/                    // UI primitives, one widget family per file
    ├── art.dart                   // ArtThumb, RemoteArt, TrackArt and the trackArtBytes helper
    ├── shell_chrome.dart          // ShellChrome: the backdrop + header every shell page wears
    ├── page_header.dart           // PageHeader, shellTrailing, and the settings/downloads route builders
    ├── backdrop.dart              // AmbientBackdrop: top-aligned radial gradient shell layer
    ├── carousel.dart              // CoverCarousel: the sliding-card deck Now Playing swipes, publishes its offset
    ├── track_title_deck.dart      // TrackTitleDeck: title/artist pairs sliding with the cover deck
    ├── track_text_morph.dart      // TrackTextMorph: title/artist Hero child, library row to Now Playing
    ├── limiter_button.dart        // LimiterButton: limiter switch with predicted gain-reduction ring
    ├── glass.dart                 // GlassContainer & FlatContainer: the frosted and flat surface primitives
    ├── sticky_header.dart         // SliverPageHeader: pinned gradient page title; SliverSectionLabel: plain section label
    ├── flat_icon_button.dart      // FlatIconButton: minimal icon button primitive
    ├── flat_slider.dart           // FlatSlider: minimal slider primitive
    ├── flat_switch.dart           // FlatSwitch: display-only switch primitive; the row owns the tap
    ├── color_seed_picker.dart     // ColorSeedPicker: HSL + hex dialog for adding a custom accent seed
    ├── track_actions.dart         // showTrackActions: per-track menu (play, play next, queue, download)
    ├── nav_rail.dart              // FloatingNavRail: bottom navigation rail
    └── styled_list_view.dart      // StyledListView: shared list & scaffolding primitive
```

> **Import Rule**: relative imports only (e.g. `import '../common/player.dart';`). No barrel files, no shared-global modules (cycles, dead code). Cross-widget state on a notifier owned by shell or service. `lib/common/states.dart` removed for this reason.

### Platform Configuration

`android/app/src/main/AndroidManifest.xml` declares the audio surface. New permission = new row here.

| Permission | Reason |
| --- | --- |
| `INTERNET` | AutoEQ, Google Fonts, remote search, downloads |
| `READ_MEDIA_AUDIO` | Media store query Android 13+; walkthrough asks |
| `READ_EXTERNAL_STORAGE` (`maxSdkVersion="32"`) | Media store query below Android 13 |
| `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`) | File into shared Music below API 29; on demand only |
| `ACCESS_MEDIA_LOCATION` | Artwork metadata |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | `audio_service` playback service |
| `WAKE_LOCK` | Playback screen off |
| `POST_NOTIFICATIONS` | Playback controls; walkthrough asks |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Keep playback service alive past OEM power management; walkthrough or Settings > Playback, never startup |
| `MODIFY_AUDIO_SETTINGS` | `AndroidEqualizer` DSP pipeline |
| `BLUETOOTH_CONNECT`, `BLUETOOTH` (`maxSdkVersion="30"`) | Bluetooth media controls |

* **Application ID / namespace**: `pharmaracist.fathom`.
* **Notification channel ID**: `pharmaracist.fathom.playback` (`player.dart`, `AudioServiceConfig`).
* **Method channels**: four, hand-registered in `MainActivity.configureFlutterEngine`, never a plugin registrant. `pharmaracist.fathom/equalizer` (`FathomEqualizerPlugin`), `pharmaracist.fathom/downloads` (`FathomDownloadsPlugin`), `pharmaracist.fathom/library` (`FathomLibraryPlugin`), `pharmaracist.fathom/power` (`FathomPowerPlugin`). Downloads takes the activity because filing below API 29 may ask for storage access; `MainActivity.onRequestPermissionsResult` forwards the answer so a held call never leaks. Library also takes the activity: deleting a file Fathom does not own needs the system's `MediaStore.createDeleteRequest` confirmation on Android 11+, and the plugin holds one call while that dialog is up; `MainActivity.onActivityResult` routes the answer back. Power takes the activity (`Context` for `PowerManager`) and its channel so the `ACTION_POWER_SAVE_MODE_CHANGED` receiver it registers while started can report back; `MainActivity.cleanUpFlutterEngine` calls `release()` so teardown leaves no receiver.
* **Remote source**: `newpipeextractor_dart` (NewPipe Extractor, native Kotlin, **GPL-3.0**). Fathom private and undistributed, so copyleft is acceptable; publishing forces GPL-3.0. Replaced `yt_flutter_musicapi` (Chaquopy CPython plus `ytmusicapi`/`yt-dlp`); native Kotlin also dropped the Python runtime and pub-cache patches. Android needs JitPack in `android/build.gradle.kts` (`allprojects.repositories`); `isCoreLibraryDesugaringEnabled = true` and `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` in `android/app/build.gradle.kts` (NewPipe targets Java 8 APIs missing below API 26). `flutter_inappwebview` exists for reCAPTCHA only, unwired.

  **Rhino ships and is reachable — do not exclude it.** The extractor depends on `org.mozilla:rhino` and runs YouTube player JavaScript when a stream URL arrives as `signatureCipher`: `VideoExtractor.getStream` → `YoutubeStreamExtractor` → `YoutubeJavaScriptPlayerManager` → `JavaScript` (Rhino). Excluding Rhino turns a build warning into `NoClassDefFoundError` on ciphered streams: unexplained resolve failure on a subset of tracks. Keep it.

* **R8 keep rules** (`android/app/proguard-rules.pro`): plugin minifies **every** release build (`FlutterPlugin.kt` sets `releaseBuildType.isMinifyEnabled = true`) and adds `proguard-android-optimize.txt`, `flutter_proguard_rules.pro`, and this module's file by convention. File name is load-bearing: do not rename; no `proguardFiles` in `build.gradle.kts` (duplicates the defaults). **Rhino is kept whole** (`org.mozilla.javascript.**`, `org.mozilla.classfile.**`): `Context` and `VMBridge` load their bridge and code generator by name, so reachability analysis strips them from call sites. A narrowed build proved it: release mapping reduced `Context` to `<clinit>` and `YoutubeSignatureUtils` held `throw null` where `Context.compileString` belongs, breaking every `signatureCipher` stream. Remaining rules are `-dontwarn`, not keeps: `java.beans.**` (JavaBeans reflection on an unused object-to-JSON path), `javax.script.**` (JSR-223 engine, unused) and `jdk.dynalink.**` (invokedynamic bootstrap in `optimizer.Bootstrapper`; Android has no call-site support). R8 cannot prove unreachability once the package is kept. Regenerate from `build/app/outputs/mapping/release/missing_rules.txt` after a dependency change.
* **`android:label`**: `Fathom`, matching `kAppName`.
* **Launcher icon pipeline**: `flutter_launcher_icons` config in `pubspec.yaml`; never hand-edit `android/app/src/main/res`. Source `assets/branding/icons/fg.svg` (tabler `wave-sine`, stroke `#FFFFFF`); rasterize `assets/branding/icons/fg.png` at 1024x1024 (`magick -background none -density 4096 fg.svg fg.png`), used as both `adaptive_icon_foreground` and `adaptive_icon_monochrome`. Pre-26 fallback `assets/branding/icons/icon_fallback.png` (black superellipse, white emblem, `python3 tool/gen_fallback_icon.py`, needs Pillow), wired as `image_path`. `tool/gen_readme_layers.py` builds `assets/branding/icons/readme_layers.png` for `README.md`. Adaptive `mipmap-anydpi-v26/ic_launcher.xml`: `@color/ic_launcher_background` (`#000000` from `values/colors.xml`) plus `@drawable/ic_launcher_foreground` and `@drawable/ic_launcher_monochrome`, inset `adaptive_icon_foreground_inset` (28%); monochrome gets the Android 13+ tint. After a source change: `python3 tool/gen_fallback_icon.py && dart run flutter_launcher_icons`.
* Manifest registers `com.ryanheise.audioservice.AudioService` (foreground `mediaPlayback`) and `MediaButtonReceiver`, both required by `audio_service`.

---

## 2. Core Domain Models

### `FathomTrack` (`lib/models/tracks.dart`)

Immutable item, either origin. Only device tracks play; remote items download first.

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
  final List<String> thumbUris; // Every thumbnail size the item carries; the download picks again from it
  final int? durationMs;     // Duration in milliseconds
  final int? dateAdded;      // Unix timestamp of file creation/addition
}
```

* **Equality**: `origin` plus identity — `id` for device, `videoId` for remote. Bare `id` is wrong for remote (ids are hashes).
* **Factories**: `FathomTrack.fromDevice(song)` parses raw `on_audio_query` objects. `FathomTrack.yt(item)` builds from a `YtItem`: a *remote item*, not playable: `uri` empty and stays empty, because no address is stored (they expire in hours) and nothing remote streams. Playable only after download, when the scan finds the file as a device track. Extractor duration is whole seconds, so `durationMs` = seconds × 1000.
* **`thumbUri` vs `thumbUris`**: `thumbUri` is the row image at `kThumbRowMaxWidth` (or `kThumbThriftyMaxWidth` under `dataSave`). `thumbUris` is every size the item carries; a download chooses again at `kThumbArtMaxWidth` for `artworkUrl`, never `thumbUri`. Both pick by encoded width, not list position (section 4).

---

## 3. State Architecture & Service Contracts

`Provider` / `ChangeNotifier`, five domains: `FathomSettings`, `FathomLibrary`, `FathomPlayer`, `FathomSearch`, `FathomDownloads`. First three long lived and notified; `FathomSearch` in-memory; `FathomDownloads` owns manifest and in-flight fetches.

### 3.1 `FathomSettings` (`lib/common/settings.dart`)

Typed store over `SharedPreferences`.

#### The `SettingKey` Enum API

```dart
enum SettingKey {
  accentIndex('fathom.accent', 0),
  fontKey('fathom.font', 'Oswald'),   // bundled or an installed Google Font; 'System' opts back out
  themeIndex('fathom.theme', 2),       // 0 = Light, 1 = Dark, 2 = Auto (follow the device)
  amoled('fathom.amoled', false),      // Pure black background behind the dark theme
  onboarded('fathom.onboarded', false),// First-run walkthrough finished
  gapless('fathom.gapless', true),
  speedIndex('fathom.speed', 1),
  sortIndex('fathom.sort', 0),
  eqEnabled('fathom.eq.enabled', true),
  eqPreset('fathom.eq.preset', null),
  limiter('fathom.eq.limiter', true),
  shuffle('fathom.shuffle', false),
  repeatIndex('fathom.repeat', 0),
  dataSave('fathom.data_save', false), // Smaller remote thumbnails, fewer rows and results
  lowEnd('fathom.low_end', false);     // Flat cards instead of frosted glass (see section 5). The user's stored choice only; power save overrides it at read time
}
```

* **Accessors**:
  * `T get<T>(SettingKey key)`: stored value or `defaultValue`.
  * `void set<T>(SettingKey key, T value)`: memory; disk when `prefKey` non-empty; `notifyListeners()` **only on real change**. Do not rely on `set` to emit for an identical value.
* **Derived read-only accessors**: `accent`, `repeatMode`, `themeMode`, `lowEndInForce` — only exceptions to "no custom getters" (6.1). They map index↔enum/swatch, nothing else. `themeMode` maps `themeIndex` 0/1/2 explicitly to `ThemeMode.light`/`dark`/`system` (enum order differs). `lowEndInForce({powerSave})` = `low_end` OR `powerSave`; battery is a parameter, not a field, and `low_end` is never written while power save is on. No other getters with mutation or caching.
* **Accent**: `settings.accent` = `settings.accentSeeds[accentIndex]` through `FathomColors.readableAccent`, HCT tone clamped ≥68 dark, ≤46 light, hue/chroma kept. Accents paint text, icons and 1px controls, so a raw dark seed on dark (or white on light) vanishes. `accentSeeds` keeps raw choices; the sheet paints the clamped color. Artwork never feeds the accent.
* **Custom seeds**: `fathom.accent.custom`, JSON ARGB ints, beside const `FathomColors.accentSwatches`. `accentSeeds` = built-ins then customs; `accentIndex` indexes the combined list, so a custom survives restart. `addAccentSeed(Color)` refuses duplicates, else append/persist/notify; the plus tile opens `color_seed_picker.dart` and selects on add. Stored custom data, not a `SettingKey`; no side effects.
* **EQ gain staging**: `_eqGains` (`fathom.eq.gains`, `hz#db` pairs). `stageEqGain(hz, db)` mutates for DSP; `commitEq()` persists; `eqGains` is unmodifiable.
* **EQ preamp**: `_eqPreamp`, `stageEqPreamp(db)`, `fathom.eq.preamp`, read as `eqPreamp`. Native (`DynamicsProcessing`) path only.
* **EQ presets**: `fathom.eq.presets`, JSON `{"<name>": {"gains": [10 values], "preamp": db, "source": "<wire>"}}`; no name collides with a built-in (`kEqPresets`). `EqPreset` is source-tagged `EqPresetSource.user` or `EqPresetSource.autoEq`; both use `saveEqPreset(name, preset)` / `applyEqPreset(name)`; `eqPresetNames(source)` renders one source, chip row built-ins then `user` then `autoEq`. Always `kEq10Bands` order plus preamp; importers map onto those bands. `FathomAutoEq` downloads `FixedBandEQ.txt` (ten filters already match) and rejects wrong filter count or centre frequencies. Gains clamp to `FathomNativeEqualizer.minDecibels`/`maxDecibels`, preamp to `maxPreampDecibels`; a document without `Preamp:` cancels the peak gain.

### 3.2 `FathomSearch` (`lib/common/search.dart`)

One field, one query; a search reaches both collections.

* `query` is the `ValueNotifier<String>` behind the rail's text box. Survives a route push, so Now Playing returns to the same text.
* `clear()` empties it ("show everything").
* No query binds to a source. The library page decides what a match means: device by title/artist, remote by asking the source. No per-source query, no "active source"; the field is the whole surface.

### 3.3 `FathomLibrary` (`lib/common/library.dart`)

Owns storage permission, scanning, image memory caching.

* **Lifecycle**: `AppLifecycleListener` refreshes the media list on return from background.
* **Status**: `FathomLibraryStatus` `idle` -> `permissionNeeded`/`loading` -> `ready`/`failure`.
* **Scans reconcile, never replace.** Download completion, rescan and lifecycle refresh all end in `applyScan`. `reconcileLibraryTracks` (`lib/common/library_diff.dart`, pure, tested) keys by origin+identity, reuses the previous `FathomTrack` when identity+metadata match, returns list + `FathomLibraryDelta` (`added`/`removed`/`moved`/`updated`). Identical scan publishes nothing (no assignment, revision bump or notification). Changed scan publishes one unmodifiable snapshot and one notification, so a one-track change is a one-track delta.
* **`revision`/`lastDelta` are the change signal.** `FathomTrack` equality stops at identity, so a metadata-only update is invisible to a deep compare; `revision` increments on every real publish and the page memoises sorted/merged lists on it. `lastDelta` names changes for addition animations.
* **Rescan keeps the list mounted.** `loading` only when no ready list exists; a `ready` refresh publishes directly, so scroll/controller/position survive. A generation guard drops an older scan finishing after a newer one.
* **Cold start paints the last scan before querying.** `restoreSnapshot` reads `library.snapshot.v1.json` from app support before the first frame; `main` awaits it, then queries. Written after every real `applyScan` via serialized temp-file rename; only device tracks with a uri. Encode on a worker isolate (`compute`) — thousands of rows stall the UI isolate; decode on the main isolate because it precedes `runApp`, where a worker hop only adds latency. A cache, not truth: scan reconciles over it; a stale row costs one correction, a lost file one slow start.
* **Artwork cache**: `Future<Uint8List?> artFor(int id)` owns album-art bytes; `Uint8List? cachedArtFor(int id)` is the synchronous read, so a route paints resolved bytes instead of a placeholder during the Hero flight. `FathomArtCache.cachedForVideo` is the remote equivalent. No parallel artwork cache (Gap 3). `ArtThumb`/`RemoteArt` decode at painted size (`Image.memory(cacheWidth/cacheHeight)` from widget size × DPR), never intrinsic: a 1000px cover for a 48px row costs megabytes and a stall.
* **Artwork URI**: `Uri? artUriForTrack(FathomTrack track)` resolves the content URI for `ArtThumb` and the lockscreen item.
* **Fetched-file fallback**: no embedded art -> `fallbackArtFor` maps media id through the manifest to videoId, returns the cached remote cover (3.5). Assigned once in `main`, so the library stays free of downloads; a non-Fathom file has no fallback.
* **Deletion is a MediaStore request, then a rescan.** `deleteTracks(tracks)` keeps device ids ≥ 0 and invokes the library channel; native deletes what Fathom owns and, on Android 11+, asks the system to confirm files it does not, holding the Dart call until answered. Only ids the platform reports gone are returned. Their art cache entries are evicted and the library reloads, so list and selection reconcile against the store rather than an optimistic edit. Callers must leave un-deleted rows selected; a partial answer is normal when the user cancels the system dialog.

### 3.4 `FathomPlayer` (`lib/common/player.dart`)

Audio engine: `just_audio`, hardware DSP, `audio_service`, queue restore.

* **Pipeline**: `AudioPlayer` with `AndroidEqualizer` via `AudioPipeline(androidAudioEffects: [...])`.
* **Playable means local.** Player holds no remote source and does not know YouTube exists. `_resolveAll(tracks)` takes only `TrackOrigin.device`; remote is dropped, because nothing plays until downloaded and scanned. No lazy resolve, no cached address, so playback never depends on an expiring stream URL.
* **Queue operations**:
  * `playFrom(List<FathomTrack> list, int index)`: replaces the queue with `AudioPlayer.setAudioSources(List<AudioSource>)`, each `AudioSource.uri(uri, tag: track.id)`, applies shuffle/loop, starts. `ConcatenatingAudioSource` is legacy; do not reintroduce.
  * `enqueue(tracks)` / `playNext(tracks)`: append after the end or after the current item; both fall back to `playFrom` when nothing plays.
  * `moveAt(int from, int to)` / `removeAt(int index)`: edit, then `_rebuildSources()` replays the queue at the same index, position and playing state. just_audio keeps its own copy, so a structural edit must not skip this.
* **List order is not play order.** `_sourceQueue` is the editable list the queue panel edits, index-aligned with engine sources. Shuffle never rewrites it: just_audio keeps its own permutation, so next is `queue[_selectedIndex + 1]` only with shuffle off. Everything answering "what comes next" asks the engine:
  * `nextTrack`/`previousTrack`: neighbour a skip lands on, in play order, or `null` when blocked. The carousel gets these, not a computed index, so side covers survive shuffle.
  * `FathomPlayer.canSkipNext`/`canSkipPrevious`: compare `AudioPlayer.nextIndex`/`previousIndex` to current. Not a repeat switch: repeat-one and a single-item queue resolve next == now; a shuffled order can have a next at the end or none at the start.
* **Media item**: `FathomPlayer._pushMediaItem()` publishes the current `MediaItem`; `playFrom`, `playIndex`, `moveAt`, `removeAt` call it. Only device tracks publish, so the uri is real; a downloaded track is a device track by then and carries its own art.
* **Deletion reaches the queue through `forgetTracks(mediaIds)`.** Removing files is not only a library concern: a deleted track may be queued or playing. The queue drops those ids; if the current track was one of them, playback stops rather than seeking into whatever takes its place, and the next survivor becomes current but stays paused. A deletion elsewhere keeps position and playing state. Deleting the whole queue clears both saved keys.
* **Queue survives cold start, not just current track.** Split across `fathom.player.state.v2` (`{queue: [FathomTrack.toJson…], index}`) and `fathom.player.position.v2` (`{id, positionMs}`). Queue writes only on change; position on a timer, so advancing one integer does not rewrite hundreds of rows. Queue JSON encodes/decodes on a worker isolate (`compute`) — hundreds of rows on the UI isolate stall every structural edit. Position names its track, applies only when the id matches the restored one, so the keys may describe different moments without seeking the wrong track. `fathom.player.state.v1` (single track) is fallback, dropped once the queue is deliberately emptied. Position is a **throttle**, not a debounce: timer only when none pending, so several events/second yield one write per five seconds. Pause, seek and `onPause`/`onDetach` flush position; index change, `playFrom`, structural edit and `dispose` flush both keys. Shuffle/repeat live outside the payload (`SettingKey.shuffle`/`repeatIndex` are written on every toggle, fresher). `restoreLastState` runs **after** `initialize` (chained in `main`), keeps device tracks with uri, rebuilds sources, seeks, no autoplay; a refused source clears queue and saved payload instead of retrying a dead file.
* **Background**: `AudioService.init` publishes the restored/playing media item and `sync()`s as soon as the handler exists; otherwise audio_service never promotes the service to foreground. Settings > Playback "Background playback" reports `FathomPowerState.isBatteryExempt` and opens the system battery-optimization screen via the power plugin, because OEM power management can reclaim even a foreground service while the app is restricted. Re-read on resume. `androidStopForegroundOnPause` stays true so a paused player releases service/wake lock; the saved queue makes that safe.

### 3.5 `FathomDownloads` (`lib/services/downloads.dart`)

Fetches remote audio and files it. Built in `main`, not by providers, because it rescans the library when a file lands: gets its own `FathomYtSource` and `onFinished`, never learns what a library is. **Only** holder of the remote source; the player has none.

* **Chain**: resolve address, stream into app temp, sniff container from first bytes, hand to Android, which tags and writes into shared Music in one native pass. Nothing durable stored on the way in (addresses expire). `source.resolve` returns cover art from the same extractor call (section 4).
* **Artwork runs alongside audio.** `_run` starts the cover fetch, then the transfer, awaiting artwork in a `finally` so a failed transfer leaves no unhandled future. Sequential awaiting cost audio **plus** art; together it costs the slower. Image is `ResolvedAudio.artwork` (largest size), fallback `FathomTrack.artworkUrl`, never `thumbUri` (row-sized, smallest under `dataSave`). Four temp paths key on `videoId`; `_waiters` rejects a second run, so no collision. Cover is remembered in `FathomArtCache` before filing, letting the library serve it via the manifest bridge when the media store has no art.
* **Manifest**: `videoId` -> MediaStore row map, `downloads.manifest.v1`. Answers: already fetched? is this track ours? which videoId owns this media id (feeds the art fallback)? Loss costs re-download and fallback cover, never correctness.
* **Metadata during save**: native tags the MP4 in-process (replaces `udta`, patches fragmented `tfhd` base offsets so YouTube's m4a is taggable), embeds cover, inserts MediaStore row, writes `TITLE`/`ARTIST`/`ALBUM`/`DURATION` on a worker thread. Untaggable (WebM, MP4 top-level `mfra`) still files with MediaStore columns and cached art; real metadata either way.
* **No remux, no FFmpeg.** Old chain wrote 3× and shelled out per track; gone. `resolve` picks the highest-bitrate m4a audio-only stream, fallback highest-bitrate audio of any container, never muxed video+audio, so no discarded video is downloaded.
* **Concurrency**: `maxConcurrent` 3; beyond that `DownloadState.pending`. `download()`'s future completes when work finishes, even if queued, so callers await a real outcome.
* **States**: `download(track)` returns false with no side effects when there is nothing to do (no remote id, already in manifest). Else `idle` -> `pending`/`running` -> `done`/`failed`; `stateOf`/`progressOf` are the menu reads. Failed retries; running/pending cannot start twice.
* **Failure reason is separate from the bool.** `failureOf(videoId)` returns why the last attempt failed, or null, cleared on retry so it never describes an in-flight attempt. Not folded into `download()`: success callers should not carry a message. The source signals failure by null, so the reason lives in one place; dropping it turns captcha/throttle/no-audio into "could not save".
* **Rescan**: manifest persists before `onFinished`, so the next scan sees a recorded row id and Downloads can join on first rebuild.
* **Notification permission** belongs to the walkthrough: `FathomDownloads.requestNotificationPermission()` is public, called by the first-run page with an explanation. Nothing requests it at construction.
* **List reads are three different things.** A surface needs outstanding work (service) and finished files (library).
  * `entries`: `DownloadEntry` work still owed — queued, running, failed with reason. Finished files are absent (library owns them). **Cached/rebuilt only on state change**, never on a progress tick; progress is per row via `progressOf`.
  * `downloadedMediaIds`: media ids Fathom fetched. **Replaced, never mutated**, so a select rebuilds on set change; a mutated list compares equal and never rebuilds. Row id `-1` = unnamed, filtered (cannot play). No library badge; remote search uses it to avoid duplicates, Downloads joins on it.
  * `forget(videoId)`: drops a failed row; device unchanged (never written). Clears the attempt so a dismissed row stays gone. Never touches the manifest, so "already fetched" remains if the file landed.
  * `forgetMediaIds(mediaIds)`: the deletion counterpart. A deleted file is not a download any more, and its manifest entry would keep the remote result permanently "already fetched" with nothing on disk. Entry, state, progress and tracked record are dropped, the media-id list is replaced (never mutated), and the manifest is persisted.
* **Network bounds, each matched to its step.** A stalled socket has no natural end; unbounded = row spins forever.
  * `resolveTimeout` 30s: source hands back an address. `_fetch`'s `connectionTimeout` covers only TCP connect; resolving is a separate round trip.
  * `transferTimeout` 10min: whole transfer, not per chunk. A server can stall mid-body and hang the `await for`; stalled and slow look identical until bounded.
  * `saveAudio` deliberately **unbounded**: native tag/file on a worker; below API 29 may hold for the storage dialog, so a Dart timeout would abort a legitimate action. No FFmpeg remux timeout; that step is gone.

---

## 4. Audio Pipeline & OS Services (`lib/services/`)

* **`FathomAudioSession`**: `AudioSession.instance` set to `AudioSessionConfiguration.music()`.
* **`FathomAudioHandler`**: `BaseAudioHandler` for MediaSession / Remote Command Center. `sync()` maps `just_audio` to `PlaybackState`: buttons gated by `canSkipNext`/`canSkipPrevious`, seek actions, `playing`, `processingState`, `updatePosition`, `bufferedPosition`, `speed`, `queueIndex`. Does **not** publish `MediaItem` (player owns it). Lock events: `play`, `pause`, `stop`, `skipToNext`, `skipToPrevious`, `seek`, `fastForward`, `rewind`.
* **`FathomNativeEqualizer`** (`lib/services/equalizer.dart`): `MethodChannel('pharmaracist.fathom/equalizer')` to the native ten-band stage. Failure tolerant; `isSupported()` false -> hardware bands. Owns `minDecibels`, `maxDecibels`, `maxPreampDecibels`.
  * **Every write reports landing.** `attach`/`setGains`/`setGain`/`setPreamp`/`setEnabled`/`setLimiter` return `bool`; `false` clears `_attached`, so a dead effect cannot absorb dial moves silently. Native returns `false` (no engine/refusal), not a throw.
  * **`isAlive()`**: health check when the Equalizer destination opens and on every new audio session; a dead effect is rebuilt on the live session.
  * **Coalesced writes**: newest gain per band (`_pendingGains`), one writer, one channel call in flight; preamp same. Frees the platform thread while a dial moves.
  * **Refusal recovers once**: reset latches, re-attach current session, replay the stored curve (staged before the write, so no value loss). A second refusal in the same drain gives up.
  * **Native `Engine` builds a fresh `EqBand` per write**, never reads channel 0 back: some HALs return a disabled/stale band, and gain on a disabled band succeeds without effect. Re-asserts `enabled` before writing (platform can disable behind the app).
* **`FathomPowerState`** (`lib/services/power.dart`): `MethodChannel('pharmaracist.fathom/power')` to Battery Saver. Built and `start()`ed in `main`, provided for surfaces. `ChangeNotifier`, not `ValueListenable<bool>`: `FathomApp` rebuilds the subtree (owns the `blurEnabled` write), the settings row only `select`s a flag. `start()` reads `isPowerSave` and subscribes to `onPowerSaveChanged`; reads `isIgnoringBatteryOptimizations`, re-reads on resume (Settings > Playback reflects a system grant). `requestBatteryExemption()` opens the screen, returns whether one opened, not whether allowed. `stop()` unsubscribes; native unregisters. Failures mean "not saving power" / "unrestricted", so a broken bridge never wedges low-end or sends the user to a screen for nothing.
* **`FathomYtSource`** (`lib/services/yt_source.dart`): remote source behind an interface; rest of Fathom never names the package. `FathomYtMusic` is the only implementation, a **fetcher, not a streamer**: no playable-now method, because a live address is fragile (expires, throttled, forces signature deciphering).
  * `initialize()` once, memoises outcome; `retry()` clears the memo for the error panel. `isReady`/`error` describe a failed start, no throw; `error` is source-wide, so an unresolvable track never writes it (would look like the whole surface is down). Setup is `LocalizationExtractor.setLocalization(language, country)`; a wrong market still searches, nonfatal.
  * `search(query, limit: quality:)` returns a stream but answers a page at once. `quality` is `YtQuality.low` or `high`, selecting a thumbnail **by encoded width**, not position: native `imagesToList` is a bare `images.map { it.url }`, discarding width/height and not sorting, making either end arbitrary. Caps in `models/ytmusic.dart` (`kThumbThriftyMaxWidth`, `kThumbRowMaxWidth`, `kThumbArtMaxWidth`) beside `pickThumbnail`/`thumbWidthOf`, pure URL logic, unit-tested. Library page owns supersession: token per keystroke, older results dropped.
  * `resolve(videoId)` resolves at fetch time for `FathomDownloads`, which downloads immediately, returning the best cover as `ResolvedAudio`. No `FathomTrack` stores an address (they expire). Null = failed download; `lastResolveError` carries why (null is ordinary, not a throw); dropping it leaves "Could not save".
  * **Artwork rides the resolve**: `getStream` already returns metadata incl. every thumbnail size beside streams, so one call yields both at no extra cost. Fixes cover art: a search `thumbUri` is row-sized and, under `dataSave`, the smallest, so reuse baked a 48px square into the file tag. `FathomTrack.artworkUrl` picks `thumbUris` at `kThumbArtMaxWidth`.
  * `pickAudioStream`: highest-bitrate m4a audio-only (taggable, usually best), fallback highest-bitrate audio of any container, never muxed.
  * Market from device locale (`FathomYtMusic.deviceCountry`, `deviceLanguage`), not a setting.
  * Failures: rate limit, reCAPTCHA, `FatalFailureException` on upstream change. Search failure leaves downloaded playback working, so it may fail loudly at search. No swallowed cause: search `onError` and download failure both carry it, because an empty state cannot distinguish "none" from "never ran", and Downloads cannot distinguish captcha from no-audio. Native Kotlin catches a failed audio fetch into an *empty list*, so refusal and genuinely-none look identical on Dart; wording claims only what it can tell apart.
* **`FathomArtCache`** (`lib/services/artwork.dart`): bytes keyed by `videoId`, not thumbnail URL (URL changes with quality, item does not). Concurrent callers share one request. A download remembers its resolved cover, so `cachedForVideo` answers without a round trip even with no thumbnail URL. Failures null; a missing thumb never breaks a row or playback.
* **`FathomFonts`** (`lib/services/fonts.dart`): `FathomFonts.instance`. `catalogue()` downloads `https://fonts.google.com/metadata/fonts` once per process, keeps latin families, orders by popularity. `install(family)` asks `https://fonts.googleapis.com/css2` for the TTF URL, writes `fonts/` under app support, registers a `FontLoader`, memoises for the session; `loadSaved()` registers earlier files at boot. `SettingKey.fontKey` = bundled (`Oswald`), `System`, or installed. Pick downloads+selects; failure keeps the sheet open with its reason.
* **`FathomAutoEq`** (`lib/services/autoeq.dart`): read-only client for the public AutoEQ catalogue at `FathomAutoEq.instance`. `entries()` caches the recommended index for the process; `fetch(entry)` downloads `FixedBandEQ.txt`, maps to `kEq10Bands`, returns a source-tagged `EqPreset`. Failures are `AutoEqException` with a display-safe message; the `Get` chip keeps its panel open for retry.

---

## 5. UI Layer & Component Hierarchy

### Shell Structure (`lib/content.dart`)

`RootShell` is a **multi-page shell**: `ShellPage` (`enum ShellPage { library, equalizer }`, carrying each header title) is the one source of truth for the visible page, held in a `ValueNotifier` the rail reads and the shell switches on. Pages are *not* pushed routes; the equalizer is a destination switched by the rail. Layered `Stack`:

1. **`ShellChrome`** (`lib/components/shell_chrome.dart`): fixed chrome — `AmbientBackdrop` behind, `PageHeader` above. Built once, *outside* the page switch, so a page change never cross-fades or duplicates them. Owns header padding (`20` gutters, `viewPadding.top + 8` top, `14` below); `PageHeader` has none, and a page adding its own drifts. Title/trailing derive from `ShellPage`, changing in place while only the body changes.
2. **`PageView`**: both destinations mounted side by side; rail tap or horizontal swipe.
3. **Dismiss layer**: `Positioned.fill` *below* `BottomPanel`, gated on search focus; outside tap closes the keyboard. Stays under the panel so its controls remain live, and separate from the page so the text-selection toolbar (root overlay) is never swallowed.
4. **`BottomPanel`** (`lib/panels/bottom_panel.dart`): `FloatingIslandPlayer` (compact mini-player, swipe-to-skip) plus `FloatingNavRail` (`lib/components/nav_rail.dart`). The rail carries the one search field bound to `FathomSearch.query`, and is the single way between destinations.

### Page Swipe (`PageView` + `_KeepAlive`)

The body is a `PageView` over `ShellPage.values`; its `index` **is** the page, no second index.

* **Rail tap**: `_goTo` writes `_page` then starts `animateToPage` without awaiting. Destination is immediate (rail, header, trailing controls change in the tap frame); the scroll carries the eye. `_pageTransitionDuration` 200ms; longer reads as waiting. Curve `FathomSpringCurve` (section 5, Motion).
* Never gated: no `_animating` lock. A second tap retargets `animateToPage`; a drag ends it and takes over. `_page` is written on tap, not completion, so no stale callback.
* **Swipe**: adopted on the page view's `ScrollEndNotification` (`_onPageSettled`) at rest, using `page.round()`. Pulled back stays; past half commits. Only `depth == 0` counts (inner scrollables bubble too). Resolves the live position, not a remembered target, so an interrupted rail move is adopted as landed; no stale token.

Both paths unfocus, collapsing an open search; a page change never strands the field and dismiss layer.

Both destinations stay **mounted**. The library is expensive (controller, memoised lists, running remote search); teardown costs a full rescan and loses it. `_KeepAlive` (`AutomaticKeepAliveClientMixin`) opts each page out of disposal. Backdrop/header sit outside the view, so they never move.

Inner horizontal drags (`SingleChildScrollView`s, chip rows) win their own gestures; only edge over-scroll reaches the view.

### Glass Surfaces (`lib/components/glass.dart`)

Two primitives; one rule:

* Floating over visible live content (sheet, mini player, inline label) ⇒ `GlassContainer`; blur separates the layer.
* Behind opaque content (rows, chips, status panel) ⇒ `FlatContainer`; sampling hidden pixels costs a `saveLayer` and shows nothing.

`GlassContainer` modes via `GlassContainer.blurEnabled`:

* **Glass** (default): `ClipRRect` > `BackdropFilter(blur)` > `AnimatedContainer`.
* **Flat**: `ClipRRect` > `AnimatedContainer`, no `BackdropFilter` in the subtree. `SettingKey.lowEnd`, "Low-end mode" in Settings > Appearance.

Mode in force: `FathomSettings.lowEndInForce` = stored preference or battery saver. Power save never writes the key; the override derives at read time, so turning it off restores the choice. While on, the row reads ON, is not tappable, reason "On: battery saver".

`FlatContainer` is **not** `GlassContainer` with a flag: no `BackdropFilter` ever, so no `saveLayer` whatever `blurEnabled` says. No `blur`/`bgOpacity`; the fill is a fixed recipe (fill + accent tint move together to stay legible). Public: `child`, `radius` 22, `accent`, `padding`, `shadow`, `borderOpacity` 0.07, `filled` true; last two only on the filled form.

`FlatContainer(filled: false)`: **outline-only** — no fill, no shadow, 1px `FathomColors.hairline`, page shows through. For cards containing row stacks with separators (Settings sections, equalizer cards). A filled body competes with content and bought a backdrop blur on the equalizer. Hairline matches the inner dividers; `borderOpacity`/`accent` do not change it. Never use outline for a card floating over live content (needs fill/blur).

Clear the floating panel: library via `StyledListView.bottomInset`; equalizer via `viewPadding.bottom + 150`. Body runs *under* `BottomPanel`; otherwise card bottoms hide behind player/rail, controls unreachable, and glass samples the card. That sampling was the most expensive part of an equalizer swipe.

Flat look: one helper `_flatDecoration`, used by both Glass's flat branch and `FlatContainer`, so no drift. Fill = accent tint (0.18 dark / 0.14 light) over bg (0.72 dark / 0.86 light), denser light (little luminance); 1px `baseOutline` (accent blended into `onSurface`, else `onSurface`) at caller opacity ×1.8, clamped light. 150ms decoration animation.

Modes stay **structurally different**: zero-sigma `BackdropFilter` still costs `saveLayer`; do not collapse.

Rail's `_RailGlass` (`lib/components/nav_rail.dart`) reads the same flag. Not a `GlassContainer` (notched clipper), but frosted over a moving page; low-end must drop it or the largest blurred band remains.

`blurEnabled` is a plain `static`: notifier would rebuild every card; parameter would thread every call site. Cost: **writing does not repaint**. One writer, `FathomApp.build`, from `settings.lowEndInForce(powerSave: widget.power.isPowerSave)`, beside `FathomColors.updateBrightness`; works because that widget rebuilds from settings and power listeners; a power-save change must repaint like a setting change. New global follows the same pattern: write from a rebuilding ancestor, document the read site. `FlatContainer` never reads it.

`FathomApp` does **not** rebuild on every settings notification. `_chromeSignature()` = resolved brightness, theme index, accent index+seed count, AMOLED, font, low-end, onboarding, power save; listener skips `setState` when unchanged. Sort/EQ/limiter are read by their owning surface; waking `MaterialApp` regenerated the scheme and rebuilt every page for nothing. `_themeFor` caches `ThemeData` per accent/brightness/font/AMOLED (`ColorScheme.fromSeed` is a full generation). `FathomPalette.readableAccent`/`onAccent` cache HCT conversions (row builds).

### Page Header (`lib/components/page_header.dart`)

`PageHeader(title, trailing)` is placed by `ShellChrome`. Library passes `shellTrailing(context)`: downloads, settings, rescan. Do not re-implement. Equalizer has no back control; the rail is the only way. `utilityRoute` is the single rise-and-fade for Settings/Downloads; `settingsRoute` builds on it.

While `FathomSelection` is active the library's trailing controls are replaced by select-all, delete and exit — the normal controls would give the mode two competing action sets. Select-all covers the **whole library**, not the rows a live search currently shows: narrowing silently would make a batch action skip tracks the user selected before typing. Delete confirms once, then calls the library, the download manifest and the player in that order, and only removes ids the platform reported gone. The title becomes the selected count. Back exits the mode instead of popping (`canPop: !selection.active`), and leaving the library destination exits it too.

### Settings and Downloads (`lib/pages/settings.dart`, `lib/pages/downloads.dart`)

Pushed utility routes, both `CustomScrollView`s. **Only the page title is sticky**: `SliverPageHeader` (`lib/components/sticky_header.dart`) pins the title over a top-opaque, bottom-transparent gradient, so rows dissolve instead of being cut. Section labels are plain `SliverSectionLabel`s that scroll; pinning them put two labels at one edge and competed with the title. Settings sections are outline `FlatContainer`s; Downloads uses the same labels for *In progress*, *Failed*, *On this device* plus the pinned title, close included.

Appearance `_showSheet` is a `GlassContainer`: accent seeds (custom picker), typography, **Get fonts**, theme, **AMOLED black**, low-end. Get fonts is a `GlassContainer` browser over `FathomFonts`: search filters, row downloads, pick installs+selects. AMOLED changes only the dark background: `FathomColors.background` returns media pure black when `_amoled` and dark; light untouched. Flag written by `FathomApp.build` beside `FathomColors.updateBrightness`.

### First Run (`lib/pages/onboarding.dart`)

`OnboardingPage` is `MaterialApp.home` while `SettingKey.onboarded` is false; finish/skip writes the key, rebuilding into `RootShell`. Five pages: welcome, library, notifications, battery exemption, feature tour. Permission pages call the same services (`FathomLibrary.load(grantIfMissing: true)`, `FathomDownloads.requestNotificationPermission()`, `FathomPowerState.requestBatteryExemption()`); no second requester or status source. Nothing at startup.

### Switch Rows

`FlatSwitch` (`lib/components/flat_switch.dart`) is **display-only**: track, thumb and tint ride one press spring, `enabled` dims, no recognizer. A settings row wraps icon/title/hint/switch in one `InkWell`, so a tap fires once; an inner recognizer would win the arena and swallow. Standalone equalizer header passes its handler; exception.

### Feedback

No **in-app transient message surface**. Feedback belongs to the owning surface:

* Playback: system media notification (`audio_service`, channel `pharmaracist.fathom.playback`), transport included.
* Downloads: Downloads page rows with the service's own reason, retry/dismiss; a finished file appears in the library.
* Failed search: library empty state names the cause, not "No matches".

No toast stack, `SnackBar`, or overlay layer. System events via notification; screen messages on the screen.

### Search Surfaces

`LibraryPage` is the search surface. No query: sorted library. Query: device matches first, remote after, under two section headers (`StyledListView.sectionFor`). Remote debounced 350ms against `FathomSearch.query`, previous stream cancelled; checked against the manifest (fetched = device, first section); tap downloads; second tap when local plays. Remote row shows a download glyph in place of play, a spinner while fetching (`_fetch` guards overlap). Outcome on Downloads; failure carries the service reason (captcha retryable, no-audio never). A throwing search sets `_ytError` from the stream, so the empty state says failed+why; unset would claim "No matches" for a search that never ran. No suggestions/browsing.

### Downloads Page (`lib/pages/downloads.dart`)

`DownloadsPage` is a pushed utility route, not a destination: rail is the only way between destinations; an unreachable page is a route, opened with `utilityRoute` from `shellTrailing`, closed with X. The one page with a back control.

Three records; two service-owned (a finished file is a library device track):

* **In progress**: queued/running; progress via `progressOf` per row (entry is cached on state change; per-tick rebuild wastes).
* **Failed**: reason on the row (causes differ: captcha retryable, no-audio not); retry clears the reason, dismiss `forget` drops the attempt without touching the manifest.
* **On this device**: fetched files joined by media id. Manifest says ours; library says title/art incl. cached remote cover. Unscanned files are absent (nothing can name them).

Tap plays in on-screen list context, pushes `nowPlayingRoute()`; a track that will not start pops the page, no dead player. No Hero tag/morph from here (belongs to library tiles/mini player); in-flight/failed covers are not shown in Now Playing.

### Track List (`lib/components/styled_list_view.dart`)

`StyledListView<T>` is the list primitive, the only thing knowing how a list meets the shell. Full body height, under header, behind player/rail; both ends deliberate.

* **Faded, not cut**: `_EdgeFade` uses `ShaderMask` + `BlendMode.dstIn` linear alpha. `dstIn` multiplies child alpha, so entrance-translucent tiles fade from current alpha, not forced opaque.
* **Shader, not `ClipRRect`, and not for cost**: both composite; a clip anti-aliases a curve, severs a row, and makes translucent tiles fight the boundary. Do not "improve" to `ClipRRect`.
* **Falloff outside insets**: heights from `topInset`/`bottomInset`; first/last rows stay clear. A short viewport (keyboard, split) means no mask, not a hidden middle.
* **Mask rows only**: `_FastScrollbar` and its label sit in the `Stack` above, so scrubbing overhangs. Keep outside.
* **Tile cannot paint outside its box**: `TrackTile` in `ClipRect`; entrance scales 96%, lifts 18px, indicator at the edge.
* **Scrollbar thumb's 56px floor yields to the track**: floor taller than the track puts `clamp`'s lower bound above its upper and throws; a short viewport is reachable. Apply only when the track can hold it.
* **Rows keyed by identity**: `StyledListView.keyFor` gives `ValueKey<LibraryTrackKey>`; `findChildIndexCallback` resolves survivors. A top insert moves elements, no invalidation of the rest; survivors keep state/offset; a new key gets its own tween. Without `keyFor`, old index path.
* **Removal not animated**: holding removed rows redefines `itemCount` and drifts indices. Rows vanish immediately; no stale rows.
* **Selection is a gesture mode, not a preference.** Long-press a device row enters `FathomSelection` with that row chosen; further long-presses toggle. While active, every row tap toggles instead of playing or fetching, and a remote result is inert (it has no file a batch action could touch), though its long-press still opens the per-track menu. The selection holds library keys, so a rescan that replaces track instances keeps it. It is shell-owned, exits when the library destination is left, and never touches disk.

### Hero Transition Pattern

Mini pill or library tile pushes `NowPlayingPage` via a custom `PageRouteBuilder`, `FathomSpringCurve`. 300ms forward, 260ms back; longer reads as waiting. One shared builder; Hero tag:

```dart
tag: 'fathom-art-${track.id}'
```

Only the *current* cover is tagged. The title/artist pair has its own hero (`fathom-text-${track.id}`): library row, mini pill and Now Playing headline all use `TrackTextMorph`, so the shuttle reads two comparable one-line layouts and interpolates their styles instead of cutting between different widgets. The carousel beside it (`_CoverCarousel`) builds exactly three cards (prev/current/next); swipes drive `skipNext`/`skipPrevious`, not a page index. A `PageView` over the queue adds a second index that disagrees on shuffle/edit; do not reintroduce. Neighbours come from `FathomPlayer.nextTrack`/`previousTrack` (play order), never `queue[selectedIndex ± 1]`.

Title/artist move on the same deck. `CoverCarousel` publishes its offset (`ValueNotifier<double>` in slots, 0 at rest); `TrackTitleDeck` (`lib/components/track_title_deck.dart`) renders three pairs translated, neighbours fading at one slot. Drag moves words; committed skip carries the old pair out with the cover; the pair also fades/rises once on open. Deck slides its own 38px, not cover spacing (narrow text would fling off). Mini pill moves art/title/artist as one face (`_PillCards`), same rule smaller.

### Motion (`lib/common/motion.dart`)

One motion language in one file. `FathomSpring` names a spring the way Apple's vocabulary does — `response` (seconds to target) and `dampingRatio` (1.0 does not overshoot) — and converts to Flutter's `SpringDescription` once, so no surface carries its own stiffness/damping constants.

`FathomMotion` presets, named by job:

* `press` 0.20s / 0.86 — touch feedback: pressed scale, slider thickness. Tiny overshoot so the control answers the finger.
* `snap` 0.30s / 1.0 — committed state: switch knob, list row height.
* `standard` 0.38s / 1.0 — a surface moved by navigation.
* `momentum` 0.40s / 0.80 — a flick or drag release, and the nav pill. The only overshoot: the finger supplied the energy.
* `gentle` 0.50s / 1.0 — large arrivals: cover scale/shadow, mini pill.

Overshoot belongs to gesture momentum only. Colours, opacity, borders and shadow stay timed: a spring on a colour overshoots into a shade nobody asked for.

`SpringValue` is the implicit-spring widget. A target change retargets the simulation from the value currently on screen, with its current velocity, so an interrupted move blends instead of jumping. `immediate` snaps while a gesture owns the value (slider fill follows the finger); `animateOnMount` travels from zero once (mini pill arrival); at rest the builder reads the target exactly, so a settled control is not a tolerance short. Do not add a second implicit-spring primitive.

Routes and stepped page moves cannot run a simulation: the navigator or `PageController` owns an `AnimationController` with a duration. `FathomSpringCurve` gives those the same decelerating arrival on normalized time — critically damped, ending exactly at 1 — and is what `utilityRoute`, `nowPlayingRoute`, rail taps, onboarding paging, the nav search switch, the track-text hero, the list entrance cascade and `kModalMotion` (every bottom sheet and dialog) use. `PageView`'s own drag settle keeps Flutter's built-in spring: it inherits the drag velocity, which a curve cannot.

Reduced motion: `utilityRoute` fades without rising; `nowPlayingRoute` swaps without a hero flight, because the shared elements have nowhere to fly. Check `MediaQuery.disableAnimationsOf(context)` before adding travel to a new route.

---

## 6. Development Conventions for Agents

1. **State mutation**: settings only via `settings.get<T>(SettingKey)` / `settings.set<T>(SettingKey, value)`. No new mutable getters/setters. Read-only derived only for documented mappings and stored custom data (`accent`, `accentSeeds`, `repeatMode`, `eqGains`, `lowEndInForce`), no mutation/cache.
2. **Re-renders**: `context.select<T, R>()` over `context.watch<T>()` in lists/high-frequency widgets; one field = `select`.
3. **Theming**: derive surfaces/dividers/text from `FathomColors` (`lib/common/colors.dart`) and `Theme.of(context).colorScheme`. Never inline `Color(0x...)`. Theme-aware (light/dark/auto via `SettingKey.themeIndex`); palette always **monochrome**: tokens resolve the active `FathomPalette` (one per brightness, fixed seed `0xFFDC8666` via `SchemeMonochrome`), repointed by `FathomApp` before the subtree builds. `SettingKey.amoled` swaps the dark background to pure black at read; light untouched. Tokens, never literals/white/black; Now Playing is the exception (`onMedia`, `mediaScrim`, `mediaBackground`).
4. **Imports**: relative only, one component family per file. No barrels/shared-global.
5. **Platform**: new Android permission + its section 1 row; keep `android:label`, App ID, channel consistent.
6. **Global render switches**: a build-read process-wide choice (exactly one: `blurEnabled`) is a `static` written from `FathomApp.build` beside `updateBrightness`, read at the widget. Not a notifier (rebuilds readers), not a parameter (threads call sites). No repaint on assignment; the writer must already rebuild. Document write/read; no second writer/global without the same justification.
7. **Motion**: springs come from `FathomMotion` (`lib/common/motion.dart`), never inline stiffness/damping or ad-hoc `AnimationController` physics. A value that must follow a gesture uses `SpringValue` with `immediate` while the finger owns it; a route or stepped page transition uses `FathomSpringCurve`. Colour, opacity, border and shadow changes stay timed.

---

## 7. Known Gaps (code must be fixed to match this document)

1. ~~Hardcoded surfaces bypass `FathomColors`.~~ Closed. All `Color(0x..)` outside `common/colors.dart` moved to tokens; `GlassContainer.surface` and switch off-constants gone; `material_color_utilities` 0.13 renamed `TonalPalette.fromHueAndChroma` to `TonalPalette.of` and `tone()` to `get()`; a bump past 0.13 needs no edits here.
2. ~~**`Colors.white` / `Colors.black` as foregrounds** in ~116 places.~~ Closed. Foregrounds are `onSurface` alpha tiers; barriers `scrim`; Now Playing uses the media tier; ink on accent fills is `FathomColors.onAccent(accent)`; the last white/black/hex outside `common/colors.dart` is gone (`Colors.transparent` aside). Do not reintroduce.
3. **Remote artwork is memory-only.** `FathomArtCache` has no disk tier; every session refetches thumbnails. Downloads are separate: a file vs a cache.
4. **`QueuePanel` labels list order "Up Next".** It renders `_sourceQueue`: right to edit, not play order under shuffle, so rows below current may not play. Showing play order makes drag-reorder ambiguous (shuffled position names no list position) — design decision, do not change silently.
5. ~~**ABI conflict blocked every build.**~~ Closed. `splits { abi { ... } }` collided with the Flutter plugin's `ndk.abiFilters`; AGP refuses ("Conflicting configuration ... in ndk abiFilters cannot be present when splits abi filters are set") during variant creation. No `afterEvaluate` fix; `disable-abi-filtering` cannot be set in `android/gradle.properties` (read via `Project.findProperty` on `:app`, which ignores properties files). Splits removed; plain `flutter build apk` gives one APK `flutter run` can install; `flutter build apk --split-per-abi` still splits on demand. Do not reintroduce without solving the injection.
6. ~~**R8 failed on reflective Rhino classes.**~~ Closed. `:app:minifyReleaseWithR8` reported six missing `java.beans`/`javax.script` classes; every release minifies, module had no `proguard-rules.pro`. Rules exist and the release build completes (22.1 MB arm64 APK, version `1.1.0+2043`, still debug-signed). The mapping keeps 493 Rhino classes, `Context` survives whole, and the DEX calls `Context.compileString` from the signature path instead of a `throw null` stub; **runtime on a ciphered stream is still unverified** (no device). Rhino must stay (section 1).

## 8. Planned Work

* **Remote artwork disk tier.** Key by `videoId`, consult before network, size-bounded (not count), never block first paint.
* **Queue search and shuffle-by-drag** unstarted/undesigned. Do not start without deciding what problem they solve.
* **reCAPTCHA navigator.** Extractor hook unset, so a challenge surfaces as failed search. Needs `flutter_inappwebview` (already pulled) and a decision on whether a browser detour belongs.
