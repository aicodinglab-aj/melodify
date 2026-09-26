import 'dart:io';
import 'dart:ui' as ui;

import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

/// Only small, validated thumbnails for the current media session. No audio is
/// copied. Sixteen disk slots bound cache size across process restarts too.
class MediaArtwork {
  MediaArtwork({OnAudioQuery? query, Future<Directory> Function()? directory})
    : _query = query ?? OnAudioQuery(),
      _directory = directory ?? getTemporaryDirectory;

  final OnAudioQuery _query;
  final Future<Directory> Function() _directory;
  final Map<int, Uri> _cache = {};
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
      final cached = _cache[song.id];
      if (cached != null && await File.fromUri(cached).exists()) return cached;
      final bytes = await _query.queryArtwork(
        song.id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 256,
        quality: 70,
      );
      if (bytes == null || bytes.isEmpty || bytes.length > 512 * 1024) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 256,
        targetHeight: 256,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
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
      _cache[song.id] = uri;
      return uri;
    } catch (_) {
      return null;
    }
  }
}
