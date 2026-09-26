import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_history.dart';

@immutable
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required Iterable<String> songKeys,
  }) : songKeys = List.unmodifiable(songKeys);

  final String id;
  final String name;
  final DateTime createdAt;
  final List<String> songKeys;

  Playlist copyWith({String? name, Iterable<String>? songKeys}) => Playlist(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    songKeys: songKeys ?? this.songKeys,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'songKeys': songKeys,
  };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final name = (json['name'] as String).trim();
    final keys = (json['songKeys'] as List).cast<String>();
    if (id.isEmpty ||
        name.isEmpty ||
        name.length > Playlists.maxNameLength ||
        keys.any((key) => key.isEmpty)) {
      throw const FormatException('Invalid playlist');
    }
    return Playlist(
      id: id,
      name: name,
      createdAt: DateTime.parse(json['createdAt'] as String),
      songKeys: keys.toSet(),
    );
  }
}

abstract interface class PlaylistsStore {
  Future<List<Playlist>> read();
  Future<void> write(List<Playlist> playlists);
}

class PreferencesPlaylistsStore implements PlaylistsStore {
  static const preferenceKey = 'melodify_playlists_v1';

  @override
  Future<List<Playlist>> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      preferenceKey,
    );
    if (raw == null) return [];
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Unsupported playlists version');
    }
    return (data['playlists'] as List)
        .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(List<Playlist> playlists) async {
    final raw = jsonEncode({
      'version': 1,
      'playlists': playlists.map((p) => p.toJson()).toList(),
    });
    if (!await (await SharedPreferences.getInstance()).setString(
      preferenceKey,
      raw,
    )) {
      throw StateError('Playlists could not be saved');
    }
  }
}

/// Shared metadata repository. The list stores creation order, each song list
/// stores insertion order; screens never read or write preferences themselves.
class Playlists extends ChangeNotifier {
  Playlists({PlaylistsStore? store})
    : _store = store ?? PreferencesPlaylistsStore();

  static const maxNameLength = 80;
  final PlaylistsStore _store;
  final _random = Random.secure();
  List<Playlist> _items = [];
  Future<void>? _restoration;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool restored = false;
  bool loadFailed = false;
  bool storageAvailable = true;
  List<Playlist> get items => List.unmodifiable(_items);
  static String keyFor(SongModel song) => PlaybackHistory.keyFor(song);

  Playlist? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> restore({bool retry = false}) {
    if (retry && loadFailed) _restoration = null;
    return _restoration ??= _restore();
  }

  Future<void> _restore() async {
    try {
      final items = await _store.read();
      if (items.map((p) => p.id).toSet().length != items.length ||
          items.map((p) => p.name.toLowerCase()).toSet().length !=
              items.length) {
        throw const FormatException('Duplicate playlists');
      }
      _items = List.of(items);
      loadFailed = false;
      storageAvailable = true;
    } catch (_) {
      loadFailed = true;
      storageAvailable = false;
    }
    restored = true;
    _notify();
  }

  Future<void> _ready() async {
    if (!restored) await restore();
    if (_disposed) throw StateError('Playlists have been disposed');
    // Do not overwrite data that could not be read, including unknown versions.
    if (loadFailed) {
      throw StateError('Restore playlists before making changes.');
    }
  }

  String _name(String input, {String? exceptId}) {
    final name = input.trim();
    if (name.isEmpty) throw const FormatException('Enter a playlist name.');
    if (name.length > maxNameLength) {
      throw const FormatException('Use 80 characters or fewer.');
    }
    if (_items.any(
      (p) => p.id != exceptId && p.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw const FormatException('A playlist with this name already exists.');
    }
    return name;
  }

  Future<Playlist> create(String name) async {
    await _ready();
    final validName = _name(name);
    String id;
    do {
      id = List.generate(
        4,
        (_) => _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
      ).join();
    } while (byId(id) != null);
    final item = Playlist(
      id: id,
      name: validName,
      createdAt: DateTime.now().toUtc(),
      songKeys: [],
    );
    _items = [item, ..._items];
    await _save();
    return item;
  }

  Playlist _require(String id) =>
      byId(id) ?? (throw StateError('This playlist no longer exists.'));

  Future<void> rename(String id, String name) async {
    await _ready();
    final item = _require(id).copyWith(name: _name(name, exceptId: id));
    _replace(item);
    await _save();
  }

  Future<void> delete(String id) async {
    await _ready();
    _require(id);
    _items = _items.where((p) => p.id != id).toList();
    await _save();
  }

  Future<int> addSongs(String id, Iterable<SongModel> songs) async {
    await _ready();
    final item = _require(id);
    final keys = {...item.songKeys, ...songs.map(keyFor)};
    final added = keys.length - item.songKeys.length;
    if (added == 0) return 0;
    _replace(item.copyWith(songKeys: keys));
    await _save();
    return added;
  }

  Future<void> removeSong(String id, SongModel song) async {
    await _ready();
    final item = _require(id);
    _replace(
      item.copyWith(
        songKeys: item.songKeys.where((key) => key != keyFor(song)),
      ),
    );
    await _save();
  }

  List<SongModel> resolve(String id, List<SongModel> library) {
    final available = {for (final song in library) keyFor(song): song};
    return (byId(id)?.songKeys ?? const <String>[])
        .map((key) => available[key])
        .whereType<SongModel>()
        .toList(growable: false);
  }

  void _replace(Playlist item) {
    _items = _items.map((p) => p.id == item.id ? item : p).toList();
  }

  Future<void> _save() {
    final snapshot = List<Playlist>.of(_items);
    _notify();
    _writes = _writes.then((_) async {
      try {
        await _store.write(snapshot);
        storageAvailable = true;
      } catch (_) {
        storageAvailable = false;
      }
      _notify();
    });
    return _writes;
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
