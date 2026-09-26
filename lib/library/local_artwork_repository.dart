import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:on_audio_query_pluse/on_audio_query.dart';

import 'playback_history.dart';

/// Lazy optional presentation data, independent of playback and library scans.
class LocalArtworkRepository {
  LocalArtworkRepository({
    OnAudioQuery? query,
    this.maxEntries = 128,
    this.maxBytes = 8 * 1024 * 1024,
  }) : _query = query ?? OnAudioQuery();
  static final shared = LocalArtworkRepository();
  final OnAudioQuery _query;
  final int maxEntries;
  final int maxBytes;
  final _cache = <String, Uint8List?>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _jobs = Queue<void Function()>();
  int _active = 0;
  int _bytes = 0;
  int get cachedEntries => _cache.length;
  int get cachedBytes => _bytes;

  static int bucket(int pixels) => pixels <= 128
      ? 128
      : pixels <= 256
      ? 256
      : 512;
  static String key(SongModel song, int pixels) =>
      '${song.id}:${PlaybackHistory.keyFor(song)}:${bucket(pixels)}';

  Future<Uint8List?> load(SongModel song, {int pixels = 128}) {
    final size = bucket(pixels);
    final id = key(song, size);
    if (_cache.containsKey(id)) {
      final data = _cache.remove(id);
      _cache[id] = data;
      return Future.value(data);
    }
    if (_pending.containsKey(id)) return _pending[id]!;
    // Bound requests during rapid scrolling as well as retained bytes.
    if (_pending.length >= 128) return Future.value(null);
    final result = Completer<Uint8List?>();
    _pending[id] = result.future;
    _jobs.add(() async {
      final data = await _read(song.id, size);
      _cache[id] = data;
      _bytes += data?.length ?? 0;
      while (_cache.length > maxEntries || _bytes > maxBytes) {
        _bytes -= _cache.remove(_cache.keys.first)?.length ?? 0;
      }
      _pending.remove(id);
      result.complete(data);
      _active--;
      _drain();
    });
    _drain();
    return result.future;
  }

  void _drain() {
    while (_active < 2 && _jobs.isNotEmpty) {
      _active++;
      _jobs.removeFirst()();
    }
  }

  Future<Uint8List?> _read(int id, int size) async {
    try {
      final bytes = await _query.queryArtwork(
        id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: size,
        quality: 70,
      );
      if (bytes == null || bytes.isEmpty || bytes.length > 512 * 1024) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: size,
        targetHeight: size,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      return bytes;
    } catch (_) {
      return null; // Cache negative results too; missing artwork is normal.
    }
  }
}
