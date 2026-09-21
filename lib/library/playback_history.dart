import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PlaybackHistoryStore {
  Future<List<String>> read();
  Future<void> write(List<String> keys);
}

class PreferencesPlaybackHistoryStore implements PlaybackHistoryStore {
  static const preferenceKey = 'melodify_recently_played_v1';

  @override
  Future<List<String>> read() async =>
      (await SharedPreferences.getInstance()).getStringList(preferenceKey) ??
      [];

  @override
  Future<void> write(List<String> keys) async {
    final saved = await (await SharedPreferences.getInstance()).setStringList(
      preferenceKey,
      keys,
    );
    if (!saved) throw StateError('History could not be saved');
  }
}

/// Stores only stable local identifiers, resolving fresh metadata from the library.
class PlaybackHistory extends ChangeNotifier {
  PlaybackHistory({PlaybackHistoryStore? store})
    : _store = store ?? PreferencesPlaybackHistoryStore();

  static const limit = 50;
  final PlaybackHistoryStore _store;
  List<String> _keys = [];
  Future<void>? _restoration;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool restored = false;
  bool storageAvailable = true;
  List<String> get keys => List.unmodifiable(_keys);

  static String keyFor(SongModel song) {
    if (song.data.trim().isNotEmpty) return 'path:${song.data}';
    if (song.uri?.isNotEmpty == true) return 'uri:${song.uri}';
    return 'id:${song.id}';
  }

  Future<void> restore() => _restoration ??= _restore();

  Future<void> _restore() async {
    try {
      _keys = (await _store.read())
          .where((key) => key.isNotEmpty)
          .toSet()
          .take(limit)
          .toList();
    } catch (_) {
      storageAvailable = false;
    }
    restored = true;
    _notify();
  }

  Future<void> record(SongModel song) async {
    await restore();
    if (_disposed) return;
    final key = keyFor(song);
    _keys = [key, ..._keys.where((item) => item != key)].take(limit).toList();
    _notify();
    final snapshot = List<String>.of(_keys);
    // Serialize writes so an older save cannot overwrite a more recent play.
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

  List<SongModel> resolve(List<SongModel> library, {int count = 10}) {
    final available = {for (final song in library) keyFor(song): song};
    return _keys
        .map((key) => available[key])
        .whereType<SongModel>()
        .take(count)
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
