# Fathom Agent Guide (`AGENTS.md`)

This guide serves as the definitive reference for AI agents working on Fathom—a high-performance, modular Flutter music player. It details the complete architecture, data flow, state management contracts, DSP audio pipeline, and UI view hierarchies.

Section 7 (`Known Gaps`) lists every place the code currently disagrees with this document. Treat section 7 as the work queue: those are code defects to fix, not contracts to copy.

---

## 1. Directory Structure & File Taxonomy

```text
lib/
├── main.dart                      // Entry point: Bootstrap, system UI, root providers. Exports FathomApp
├── content.dart                   // RootShell: IndexedStack shell, backdrop wrapper, BottomPanel overlay
├── models/
│   └── tracks.dart                // Domain model: FathomTrack & serialization factories
├── common/
│   ├── colors.dart                // FathomColors: palette constants, accent swatches, glass tokens
│   ├── constants.dart             // App metadata, EQ band tables, speed presets, FathomRepeatMode, formatters
│   ├── settings.dart              // FathomSettings: unified enum-based key-value preferences store
│   ├── library.dart               // FathomLibrary: storage permission handling, media querying, art caching
│   └── player.dart                // FathomPlayer: just_audio engine, queue management, palette extraction
├── services/
│   ├── audio.dart                 // FathomAudioSession & FathomAudioHandler (audio_service lockscreen controls)
│   └── autoeq.dart                // FathomAutoEq: AutoEQ catalogue index and ten band result fetch/parse
├── panels/
│   ├── bottom_panel.dart          // FloatingIslandPlayer: compact player island, Now Playing push
│   └── queue.dart                 // Drag-and-drop up-next queue drawer
├── pages/
│   ├── library.dart               // Track list view with alphabet scrubbing, search filtering, sort modal
│   ├── equalizer.dart             // 10-band DSP equalizer, preset save/edit and AutoEQ import
│   ├── playing.dart               // Full-screen Now Playing view with cover carousel & volume control
│   └── settings.dart              // App settings interface (typography, accent swatches, gapless toggle)
└── components/                    // UI primitives, one widget family per file
    ├── art.dart                   // ArtThumb: hero-tagged album art with in-memory byte cache
    ├── backdrop.dart              // AmbientBackdrop: top-aligned radial gradient shell layer
    ├── glass.dart                 // GlassContainer: frosted-glass surface primitive
    ├── flat_icon_button.dart      // FlatIconButton: minimal icon button primitive
    ├── flat_slider.dart           // FlatSlider: minimal slider primitive
    ├── nav_rail.dart              // FloatingNavRail: bottom navigation rail
    └── styled_list_view.dart      // StyledListView: shared list & scaffolding primitive
```

> **Import Rule**: Always use direct relative imports (e.g., `import '../common/player.dart';`). Barrel files and shared-global modules (the legacy `states.dart`) are strictly prohibited — they cause circular dependencies and dead code bloat. `lib/common/states.dart` still exists in violation of this rule; see Known Gaps 1.

### Platform Configuration

`android/app/src/main/AndroidManifest.xml` declares the audio platform surface. Permissions are deliberate; adding one requires a documentation update here.

| Permission | Reason |
| --- | --- |
| `INTERNET` | AutoEQ catalogue downloads from the equalizer page |
| `READ_MEDIA_AUDIO` | Media store query on Android 13+ |
| `READ_EXTERNAL_STORAGE` (`maxSdkVersion="32"`) | Media store query below Android 13 |
| `ACCESS_MEDIA_LOCATION` | Artwork metadata access |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | `audio_service` playback service |
| `WAKE_LOCK` | Playback continues with screen off |
| `POST_NOTIFICATIONS` | Playback notification controls |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevents playback service being killed |
| `MODIFY_AUDIO_SETTINGS` | `AndroidEqualizer` DSP pipeline |
| `BLUETOOTH_CONNECT`, `BLUETOOTH` (`maxSdkVersion="30"`) | Bluetooth media controls |

* **Application ID / namespace**: `pharmaracist.fathom`.
* **Notification channel ID**: `pharmaracist.fathom.playback` (`player.dart`, `AudioServiceConfig`).
* **`android:label`**: `Fathom`, matching `kAppName`.
* The manifest also registers `com.ryanheise.audioservice.AudioService` (foreground type `mediaPlayback`) and `MediaButtonReceiver`, both required by `audio_service`.

---

## 2. Core Domain Models

### `FathomTrack` (`lib/models/tracks.dart`)

Immutable model representing a media item retrieved from local storage.

```dart
@immutable
class FathomTrack {
  final int id;            // Unique device media store ID (used as Hero tag & art cache key)
  final String title;      // Track title (defaults to "Untitled")
  final String artist;     // Artist name (defaults to "Unknown Artist")
  final String uri;        // File content URI string
  final int? durationMs;   // Duration in milliseconds
  final int? dateAdded;    // Unix timestamp of file creation/addition
}
```

* **Equality**: Derived strictly from `id` (`operator ==` and `hashCode`).
* **Factories**: `FathomTrack.fromDevice(song)` parses raw `on_audio_query` objects. `FathomTrack.fromMap(map)` and `toMap()` are the JSON/map serialization pair; keep their keys in sync (`id`, `title`, `artist`, `uri`, `duration`, `dateAdded`).

---

## 3. State Architecture & Service Contracts

State is driven by `Provider` / `ChangeNotifier` and divided into three independent domains: `FathomSettings`, `FathomLibrary`, and `FathomPlayer`.

### 3.1 `FathomSettings` (`lib/common/settings.dart`)

Unified, strongly typed settings store backed by `SharedPreferences`.

#### The `SettingKey` Enum API

```dart
enum SettingKey {
  accentIndex('fathom.accent', 0),
  useArtAccent('fathom.art_accent', false),
  fontKey('fathom.font', 'System'),   // see Known Gaps 3
  gapless('fathom.gapless', true),
  speedIndex('fathom.speed', 1),
  sortIndex('fathom.sort', 0),
  eqEnabled('fathom.eq.enabled', true),
  eqPreset('fathom.eq.preset', null),
  shuffle('fathom.shuffle', false),
  repeatIndex('fathom.repeat', 0),
  searchQuery('', ''); // In-memory only; empty prefKey means "never persisted"
}
```

* **Accessors**:
  * `T get<T>(SettingKey key)`: returns the stored value, or the key's `defaultValue` when unset.
  * `void set<T>(SettingKey key, T value)`: updates memory, persists to disk when `prefKey` is non-empty, and calls `notifyListeners()` **only when the value actually changed**. Callers must not rely on `set` to emit when writing an identical value.
* **Derived read-only accessors**: `accent` and `repeatMode` are the sanctioned exceptions to the "no custom getters" rule in section 6.1. They encapsulate the index↔enum and index↔swatch mapping, nothing else. Do not add further getters with mutation or caching side effects.
* **Dynamic accent resolution**: `settings.accent` returns the `PaletteGenerator`-extracted artwork accent while `useArtAccent == true` and an extracted color exists; otherwise it falls back to `FathomColors.accentSwatches[accentIndex]`.
* **EQ gain staging**: gains are stored out-of-band in `_eqGains` (persisted under `fathom.eq.gains` as `hz#db` pairs). `stageEqGain(hz, db)` mutates the live map for immediate DSP feedback; `commitEq()` persists. `eqGains` returns an unmodifiable view.
* **EQ preamp**: the input gain applied before the band filters is `_eqPreamp`, staged by `stageEqPreamp(db)`, persisted under `fathom.eq.preamp`, and read back as `eqPreamp`. It only reaches DSP on the native (`DynamicsProcessing`) path.
* **EQ presets**: named curves are persisted under `fathom.eq.presets` as JSON `{"<name>": {"gains": [10 values], "preamp": db, "source": "<wire>"}}`, and the store never holds a name that collides with a built-in (`kEqPresets`). `EqPreset` is source-tagged: `EqPresetSource.user` for curves saved on the equalizer page, `EqPresetSource.autoEq` for curves imported from the AutoEQ catalogue. Both kinds go through the same `saveEqPreset(name, preset)` / `applyEqPreset(name)` path, and `eqPresetNames(source)` lets a surface render one source at a time: the equalizer chip row lists built-ins, then `user`, then `autoEq`. Presets are always `kEq10Bands` order plus a preamp, so an importer must map its curve onto those ten bands. The AutoEQ importer (`FathomAutoEq`) does exactly that: it downloads `FixedBandEQ.txt`, whose ten filters already match `kEq10Bands`, and rejects any document whose filter count or centre frequencies do not line up. Gains are clamped to `FathomNativeEqualizer.minDecibels`/`maxDecibels` and the preamp to `maxPreampDecibels`; when a document omits its own `Preamp:` the peak gain is cancelled instead.

### 3.2 `FathomLibrary` (`lib/common/library.dart`)

Manages system audio storage access, background scanning, and image memory caching.

* **Lifecycle awareness**: uses `AppLifecycleListener` to refresh the media list when returning from background.
* **Status pipeline**: `FathomLibraryStatus` transitions `idle` -> `permissionNeeded` / `loading` -> `ready` / `failure`.
* **Artwork cache**: `Future<Uint8List?> artFor(int id)` is the single owner of cached album artwork bytes. It eliminates scroll stutter in lists; no other component may keep a parallel artwork cache (Known Gaps 7).
* **Artwork URI**: `Uri? artUriForTrack(FathomTrack track)` resolves the artwork content URI used by `ArtThumb` and the backdrop.

### 3.3 `FathomPlayer` (`lib/common/player.dart`)

Central audio engine linking `just_audio`, hardware DSP effects, `audio_service`, and dynamic color extraction.

* **Audio pipeline**: initializes `AudioPlayer` with an `AndroidEqualizer` attached via `AudioPipeline(androidAudioEffects: [...])`.
* **Queue operations**:
  * `playFrom(List<FathomTrack> list, int index)`: replaces the engine queue using `AudioPlayer.setAudioSources(List<AudioSource>)` where each entry is `AudioSource.uri(uri, tag: track.id)`, then applies shuffle and loop mode and starts playback. `ConcatenatingAudioSource` is the legacy mechanism and must not be reintroduced.
  * `moveAt(int from, int to)` and `removeAt(int index)`: reorder and remove entries. These must keep the audible engine queue and the UI queue in lockstep while playback continues uninterrupted. Today they mutate only the local queue (Known Gaps 2).
* **Media item ownership**: `_pushMediaItem()` publishes the `MediaItem` for the current track to `FathomAudioHandler`; `playFrom`, `playIndex`, `moveAt`, and `removeAt` all call it.
* **Palette extraction**: on track change, when `useArtAccent == true`, `_extractArtAccent(trackId)` samples dominant vibrant colors from the artwork and calls `settings.updateArtAccent(color)`.

---

## 4. Audio Pipeline & OS Services (`lib/services/`)

* **`FathomAudioSession`**: configures hardware output via `AudioSession.instance` set to `AudioSessionConfiguration.music()`.
* **`FathomAudioHandler`**: subclasses `BaseAudioHandler` to interface with native OS playback services (Android MediaSession / iOS Remote Command Center).
  * `sync()` maps `just_audio` state onto an OS-level `PlaybackState`: control buttons (`skipToPrevious` / `play` / `pause` / `skipToNext`, gated by `FathomPlayer.canSkipNext` / `canSkipPrevious`), seek system actions, `playing`, `processingState`, `updatePosition`, `bufferedPosition`, `speed`, and `queueIndex`. `sync()` does **not** publish `MediaItem`; that belongs to `FathomPlayer._pushMediaItem()`.
  * Handles lock screen events: `play`, `pause`, `stop`, `skipToNext`, `skipToPrevious`, `seek`, `fastForward`, `rewind`.
* **`FathomNativeEqualizer`** (`lib/services/equalizer.dart`): `MethodChannel('pharmaracist.fathom/equalizer')` bridge to the native ten band stage. Every call is failure tolerant; when `isSupported()` reports false the player keeps the hardware bands. Owns the gain and preamp ranges (`minDecibels`, `maxDecibels`, `maxPreampDecibels`).
* **`FathomAutoEq`** (`lib/services/autoeq.dart`): read-only client for the public AutoEQ catalogue, reachable as the `FathomAutoEq.instance` singleton. `entries()` downloads and caches the recommended-results index for the process lifetime; `fetch(entry)` downloads one `FixedBandEQ.txt` and maps it onto `kEq10Bands`, returning a source-tagged `EqPreset`. Failures surface as `AutoEqException` with a message safe to display; the equalizer page's `Get` chip keeps its panel open so the user can retry.

---

## 5. UI Layer & Component Hierarchy

### Shell Structure (`lib/content.dart`)

`RootShell` renders a layered `Stack`:

1. **`AmbientBackdrop`** (`lib/components/backdrop.dart`): top-aligned radial gradient reflecting the current primary accent color, animated over 400ms with `Curves.easeOutCubic`.
2. **`IndexedStack`**: displays lazy-loaded, persistent pages (`LibraryPage`, `EqualizerPage`).
3. **`BottomPanel`** (`lib/panels/bottom_panel.dart`): combines `FloatingIslandPlayer` (compact mini-player with horizontal swipe-to-skip gestures) and `FloatingNavRail` (`lib/components/nav_rail.dart`).

### Hero Transition Pattern

Tapping the mini-player pill or a track tile in `LibraryPage` pushes `NowPlayingPage` through a custom `PageRouteBuilder` using `Curves.easeInOutCubic`. There must be exactly one shared route builder for this transition; the cover art morphs across screens using the Hero tag format:

```dart
tag: 'fathom-art-${track.id}'
```

---

## 6. Development Conventions for Agents

1. **State mutation**: reach settings exclusively through `settings.get<T>(SettingKey)` / `settings.set<T>(SettingKey, value)`. Do not add new mutable getters or setters to `FathomSettings`. Read-only derived getters are permitted only for documented key mappings (`accent`, `repeatMode`, `eqGains`) and must have no mutation or caching side effects.
2. **Re-renders**: prefer `context.select<T, R>()` over `context.watch<T>()` in lists and high-frequency widgets; if a widget reads a single field from a notifier, use `select` for that field.
3. **Theming**: derive surfaces, dividers, and text styles from `FathomColors` (`lib/common/colors.dart`) and `Theme.of(context).colorScheme`. Never inline a literal `Color(0x...)` in a widget. Maintain `Brightness.dark` throughout all new components.
4. **Imports**: direct relative imports only, one component family per file. No barrel files, no shared-global modules.
5. **Platform surface**: declare a new Android permission only together with its row in section 1, and keep the manifest `android:label`, application ID, and notification channel ID consistent with section 1.

---

## 7. Known Gaps (code must be fixed to match this document)

1. **`lib/common/states.dart` violates the import rule.** Four lines of shared globals (`heroFromPanel`, `searchQuery`) are imported by `lib/pages/library.dart:8` and `lib/panels/bottom_panel.dart:5`, with writes at `library.dart:250,365` and `bottom_panel.dart:52,55,200,269`. Move hero-origin state onto the shell/player domain and live search state into `FathomSettings`, then delete the file.
2. **`FathomPlayer.moveAt` / `removeAt` diverge from the engine queue.** `player.dart:174-211` rewrites only `_sourceQueue`. The `AudioPlayer` playlist is never reordered (`moveAudioSource`) or trimmed (`removeAudioSourceAt`), so the drawer order and the audible order disagree after an edit. Section 3.3 requires lockstep.
3. **`fontKey` default disagreement.** `settings.dart:10` defaults to `'Oswald'`; sections 1 and 3.1 document `'System'`, and `kFontOptions = ['System', 'Oswald']` (`constants.dart:7`) lists System first. Decide the canonical default, then align code and this document.
4. **Now Playing route is inconsistent and duplicated.** The tile path uses `Curves.easeOut` (`library.dart:78`) while the panel path uses `Curves.easeInOutCubic` (`bottom_panel.dart:286`), and the route builder is written twice (`library.dart:70-98`, `bottom_panel.dart:276-290`). Section 5 requires one shared builder using `easeInOutCubic`.
5. **Over-broad provider subscription.** `equalizer.dart:35` uses `context.watch<FathomPlayer>()` but reads only `eqReady`; use `context.select`. Convention 6.2.
6. **Hardcoded surfaces bypass `FathomColors`.** Literal colors at `settings.dart:16,17,18,53`, `playing.dart:188,189,323`, and `glass.dart:28` (`surface = Color(0xFF111111)`) shadow `FathomColors.surface` / `GlassContainer` glass tokens (`colors.dart:19,23,24`). Convention 6.3.
7. **Duplicate artwork cache.** `art.dart:56` keeps a static `_memCache` alongside `FathomLibrary.artFor` (`library.dart`), and `playing.dart:159` re-fetches the same bytes. `FathomLibrary.artFor` is the single owner per section 3.2.
8. **`test/widget_test.dart` asserts nothing.** It pumps a bare `SizedBox` and asserts that it exists, so the suite cannot catch a broken `FathomApp` startup. Replace with a `FathomApp` smoke test or delete.
