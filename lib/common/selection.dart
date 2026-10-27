import 'package:flutter/foundation.dart';

import '../models/tracks.dart';
import 'library_diff.dart';

/// Which device tracks the library has selected for a future batch action.
///
/// The selection is an in-memory mode, not a preference: it is owned by the
/// shell, cleared whenever the library stops being the surface it describes,
/// and never written to disk. It deliberately holds keys rather than tracks so
/// a rescan that replaces a track instance does not drop the selection.
///
/// Only device tracks are selectable. A remote result is a thing to download,
/// not a file that a batch action could delete or play, so every mutator
/// rejects it without changing state.
class FathomSelection extends ChangeNotifier {
  bool _active = false;
  final Set<LibraryTrackKey> _keys = <LibraryTrackKey>{};

  /// Whether the library is in selection mode. Mode and contents are separate:
  /// entering with nothing selected is a valid state, and clearing every key
  /// through [toggleAll] leaves the mode on so the user can pick another set.
  bool get active => _active;

  /// How many device tracks are selected.
  int get count => _keys.length;

  /// The selected identities, for a future batch action to resolve.
  Set<LibraryTrackKey> get keys => Set<LibraryTrackKey>.unmodifiable(_keys);

  /// Whether [track] is a selected device track.
  bool isSelected(FathomTrack track) =>
      track.origin == TrackOrigin.device &&
      _keys.contains(libraryTrackKey(track));

  /// Enters selection mode with nothing selected.
  void begin() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Adds or removes one device track.
  ///
  /// Remote items are ignored: a row that is not on the device has nothing a
  /// batch action could act on. Toggling while inactive enters the mode, so the
  /// row's own tap is enough to start selecting and no separate mode flag has
  /// to be kept in step with the first key.
  void toggle(FathomTrack track) {
    if (track.origin != TrackOrigin.device) return;
    final key = libraryTrackKey(track);
    if (!_keys.add(key)) _keys.remove(key);
    _active = true;
    notifyListeners();
  }

  /// Selects every device track in [tracks], entering selection mode.
  ///
  /// Remote items in the iterable are skipped. The caller decides which list
  /// this covers: the header passes the whole library, not the filtered rows,
  /// so a search does not silently narrow what "all" means.
  void selectAll(Iterable<FathomTrack> tracks) {
    var changed = !_active;
    _active = true;
    for (final track in tracks) {
      if (track.origin != TrackOrigin.device) continue;
      if (_keys.add(libraryTrackKey(track))) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Selects every device track when they are not all selected, otherwise
  /// clears the selection while staying in selection mode.
  void toggleAll(Iterable<FathomTrack> tracks) {
    final deviceTracks = <FathomTrack>[];
    for (final track in tracks) {
      if (track.origin == TrackOrigin.device) deviceTracks.add(track);
    }
    final allSelected = deviceTracks.isNotEmpty &&
        deviceTracks.every((track) => _keys.contains(libraryTrackKey(track)));

    if (allSelected) {
      final changed = _keys.isNotEmpty || !_active;
      _keys.clear();
      _active = true;
      if (changed) notifyListeners();
      return;
    }

    var changed = !_active;
    _active = true;
    for (final track in deviceTracks) {
      if (_keys.add(libraryTrackKey(track))) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Drops the keys for media ids that no longer exist after a delete.
  ///
  /// A deleted track cannot stay selected, but an untouched key must survive a
  /// partial failure. The mode ends once no key is left, which is what makes a
  /// successful batch delete collapse the header back to the normal controls.
  void removeDeleted(Set<int> mediaIds) {
    if (mediaIds.isEmpty) return;
    final before = _keys.length;
    _keys.removeWhere(
      (key) => key.$1 == TrackOrigin.device && mediaIds.contains(key.$2),
    );
    if (_keys.length == before) return;
    if (_keys.isEmpty) _active = false;
    notifyListeners();
  }

  /// Leaves selection mode and drops every key.
  void exit() {
    if (!_active && _keys.isEmpty) return;
    _active = false;
    _keys.clear();
    notifyListeners();
  }

  /// Alias for [exit]: empties the keys and leaves the mode.
  void clear() => exit();
}
