import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_history.dart';

abstract interface class FavoritesStore {
  Future<List<String>> read();
  Future<void> write(List<String> keys);
}

class PreferencesFavoritesStore implements FavoritesStore {
  static const preferenceKey = 'melodify_favorites_v1';

  @override
  Future<List<String>> read() async =>
      (await SharedPreferences.getInstance()).getStringList(preferenceKey) ??
      [];

  @override
  Future<void> write(List<String> keys) async {
    if (!await (await SharedPreferences.getInstance()).setStringList(
      preferenceKey,
      keys,
    )) {
      throw StateError('Favorites could not be saved');
    }
  }
}

/// One observable, ordered set of identifiers; no audio or metadata is copied.
class Favorites extends ChangeNotifier {
  Favorites({FavoritesStore? store})
    : _store = store ?? PreferencesFavoritesStore();

  final FavoritesStore _store;
  List<String> _keys = [];
  Future<void>? _restoration;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool restored = false;
  bool storageAvailable = true;
  List<String> get keys => List.unmodifiable(_keys);

  static String keyFor(SongModel song) => PlaybackHistory.keyFor(song);
  bool isLiked(SongModel song) => _keys.contains(keyFor(song));

  Future<void> restore() => _restoration ??= _restore();

  Future<void> _restore() async {
    try {
      _keys = (await _store.read())
          .where((key) => key.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      storageAvailable = false;
    }
    restored = true;
    _notify();
  }

  Future<void> like(SongModel song) => _change(song, true);
  Future<void> unlike(SongModel song) => _change(song, false);
  Future<void> toggle(SongModel song) => _change(song, null);

  Future<void> _change(SongModel song, bool? liked) async {
    if (!restored) await restore();
    if (_disposed) return;
    final key = keyFor(song);
    final current = _keys.contains(key);
    final next = liked ?? !current;
    if (next == current) return;
    _keys = [if (next) key, ..._keys.where((item) => item != key)];
    _notify();
    final snapshot = List<String>.of(_keys);
    // Keep rapid toggles durable in the same order as their UI updates.
    _writes = _writes.then((_) async {
      try {
        await _store.write(snapshot);
        storageAvailable = true;
      } catch (_) {
        storageAvailable = false;
      }
      _notify();
    });
    await _writes;
  }

  /// Missing files remain stored, but cannot enter a new playable queue.
  List<SongModel> resolve(List<SongModel> library) {
    final available = {for (final song in library) keyFor(song): song};
    return _keys
        .map((key) => available[key])
        .whereType<SongModel>()
        .toList(growable: false);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
