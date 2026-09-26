import 'dart:io';

import '../library/local_artwork_repository.dart';

import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

/// Only small, validated thumbnails for the current media session. No audio is
/// copied. Sixteen disk slots bound cache size across process restarts too.
class MediaArtwork {
  MediaArtwork({OnAudioQuery? query, Future<Directory> Function()? directory})
    : _artwork = query == null
          ? LocalArtworkRepository.shared
          : LocalArtworkRepository(query: query),
      _directory = directory ?? getTemporaryDirectory;

  final LocalArtworkRepository _artwork;
  final Future<Directory> Function() _directory;
  final Map<String, Uri> _cache = {};
  Future<void> _work = Future.value();
  int _slot = 0;

  Future<Uri?> resolve(SongModel song) {
    // Serial work also bounds simultaneous decoder/plugin calls on rapid Next.
    final result = _work.then((_) => _resolve(song));
    _work = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Uri?> _resolve(SongModel song) async {
    try {
      final key = LocalArtworkRepository.key(song, 256);
      final cached = _cache[key];
      if (cached != null && await File.fromUri(cached).exists()) return cached;
      final bytes = await _artwork.load(song, pixels: 256);
      if (bytes == null) return null;
      final root = await _directory();
      final directory = Directory('${root.path}/melodify_media_artwork');
      await directory.create(recursive: true);
      final prefix = 'slot_${_slot++ % 16}_';
      await for (final entry in directory.list()) {
        if (entry is File && entry.uri.pathSegments.last.startsWith(prefix)) {
          _cache.removeWhere((_, uri) => uri == entry.uri);
          await entry.delete();
        }
      }
      final file = File(
        '${directory.path}/$prefix${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      final uri = file.uri;
      _cache[key] = uri;
      // Temporary files may be removed by the OS between lookups, so bound the
      // index independently of the slot-file eviction above.
      while (_cache.length > 16) {
        _cache.remove(_cache.keys.first);
      }
      return uri;
    } catch (_) {
      return null;
    }
  }
}
