# Fathom Agent Guide (`AGENTS.md`)

This guide serves as the definitive reference for AI agents working on Fathom—a high-performance, modular Flutter music player. It details the complete architecture, data flow, state management contracts, DSP audio pipeline, and UI view hierarchies.

---

## 1. Directory Structure & File Taxonomy

```text
lib/
├── main.dart                      // Entry point: Bootstrap, system UI, root providers
├── content.dart                   // Shell layout: Ambient backdrop, IndexedStack, BottomPanel overlay
├── models/
│   └── tracks.dart                // Domain model: FathomTrack & serialization factories
├── common/
│   ├── colors.dart                // Palette constants, accent swatches, glass tokens
│   ├── constants.dart             // App metadata, EQ band tables, speed presets, formatters
│   ├── settings.dart              // FathomSettings: Unified enum-based Key-Value preferences store
│   ├── library.dart               // FathomLibrary: Storage permission handling, media querying, art caching
│   └── player.dart                // FathomPlayer: just_audio engine, queue management, PaletteGenerator integration
├── services/
│   └── audio.dart                 // FathomAudioSession & FathomAudioHandler (audio_service lockscreen controls)
├── panels/
│   ├── bottom_panel.dart          // Integrated floating player island & navigation rail
│   └── queue.dart                 // Drag-and-drop up-next queue drawer
├── pages/
│   ├── library.dart               // Track list view with alphabet scrubbing, search filtering, and sort modal
│   ├── equalizer.dart             // 10-band DSP equalizer sliders & preset switcher
│   ├── playing.dart               // Full-screen Now Playing view with cover carousel & volume control
│   └── settings.dart              // App settings interface (typography, accent swatches, gapless toggle)
└── components/                    // UI Primitives: ArtThumb, GlassContainer, FlatIconButton, FlatSlider, StyledListView

```

> **Import Rule**: Always use direct relative imports (e.g., `import '../common/player.dart';`). Barrel files (such as the legacy `states.dart`) are strictly prohibited to prevent circular dependencies and dead code bloat.

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
* **Factories**: `FathomTrack.fromDevice(song)` parses raw `on_audio_query` objects, and `FathomTrack.fromMap(map)` supports JSON/map serialization.

---

## 3. State Architecture & Service Contracts

State is driven by `Provider` / `ChangeNotifier` and divided into three independent domains:

### 3.1 `FathomSettings` (`lib/common/settings.dart`)

Unified, strongly typed settings store backed by `SharedPreferences`.

#### The `SettingKey` Enum API

```dart
enum SettingKey {
  accentIndex('fathom.accent', 0),
  useArtAccent('fathom.art_accent', false),
  fontKey('fathom.font', 'System'),
  gapless('fathom.gapless', true),
  speedIndex('fathom.speed', 1),
  sortIndex('fathom.sort', 0),
  eqEnabled('fathom.eq.enabled', true),
  eqPreset('fathom.eq.preset', null),
  shuffle('fathom.shuffle', false),
  repeatIndex('fathom.repeat', 0),
  searchQuery('', ''); // In-memory only
}

```

* **Accessors**:
* `T get<T>(SettingKey key)`: Retrieves value or default.
* `void set<T>(SettingKey key, T value)`: Updates memory, persists to disk (if `prefKey` is set), and triggers `notifyListeners()`.


* **Dynamic Accent Resolution**:
* `settings.accent`: Computes either the current `PaletteGenerator` extracted artwork accent (if `useArtAccent == true`) or falls back to `FathomColors.accentSwatches[accentIndex]`.



---

### 3.2 `FathomLibrary` (`lib/common/library.dart`)

Manages system audio storage access, background scanning, and image memory caching.

* **Lifecycle Awareness**: Uses `AppLifecycleListener` to automatically refresh the media list when returning from background.
* **Status Pipeline**: Transitions through `FathomLibraryStatus`: `idle` $\rightarrow$ `permissionNeeded` / `loading` $\rightarrow$ `ready` / `failure`.
* **Artwork Cache**: `Future<Uint8List?> artFor(int id)` caches album artwork byte arrays in memory to eliminate scroll stutter in lists.

---

### 3.3 `FathomPlayer` (`lib/common/player.dart`)

Central audio engine linking `just_audio`, hardware DSP effects, `audio_service`, and dynamic color extraction.

* **Audio Pipeline**: Initializes `AudioPlayer` with an `AndroidEqualizer` pipeline effect attached.
* **Queue Operations**:
* `playFrom(List<FathomTrack> list, int index)`: Generates a `ConcatenatingAudioSource` and commences playback.
* `moveAt(int from, int to)` & `removeAt(int index)`: Updates queue state live without interrupting audio output.


* **Palette Extraction**:
* On track change, if `useArtAccent` is `true`, `_extractArtAccent(trackId)` extracts dominant vibrant colors from the artwork and calls `settings.updateArtAccent(color)`.



---

## 4. Audio Pipeline & OS Services (`lib/services/audio.dart`)

* **`FathomAudioSession`**: Configures hardware output via `AudioSession.instance` set to `AudioSessionConfiguration.music()`.
* **`FathomAudioHandler`**: Subclasses `BaseAudioHandler` to interface with native OS playback services (Android MediaSession / iOS Remote Command Center):
* Exposes `sync()` to map internal `just_audio` state to OS-level `PlaybackState` and `MediaItem` controls.
* Handles lock screen events (`play`, `pause`, `skipToNext`, `skipToPrevious`, `seek`, `fastForward`, `rewind`).



---

## 5. UI Layer & Component Hierarchy

### Shell Structure (`lib/content.dart`)

The application frame renders a layered `Stack`:

1. **`AmbientBackdrop`**: Top-aligned radial gradient reflecting the current primary accent color with a smooth 400ms transition.
2. **`IndexedStack`**: Displays lazy-loaded, persistent pages (`LibraryPage`, `EqualizerPage`).
3. **`BottomPanel` (`lib/panels/bottom_panel.dart`)**: Combines `FloatingIslandPlayer` (compact mini-player with horizontal swipe-to-skip gestures) and `FloatingNavRail`.

### Hero Transition Pattern

When tapping the mini-player pill or any track tile in `LibraryPage`, the app pushes `NowPlayingPage` using a custom `PageRouteBuilder` with `Curves.easeInOutCubic`. The cover art morphs seamlessly across screens using the Hero tag format:

```dart
tag: 'fathom-art-${track.id}'

```

---

## 6. Development Conventions for Agents

1. **State Mutation**: Never write custom getters/setters in `FathomSettings`. Always utilize `settings.get<T>(SettingKey)` and `settings.set<T>(SettingKey, value)`.
2. **Re-renders**: Prefer `context.select<T, R>()` over `context.watch<T>()` in lists and high-frequency widgets to constrain rebuild scopes.
3. **Theming**: Derive surfaces and text styles from `FathomColors` (`lib/common/colors.dart`) and `Theme.of(context).colorScheme`. Maintain `Brightness.dark` throughout all new components.
