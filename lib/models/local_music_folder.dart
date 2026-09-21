import 'package:on_audio_query_pluse/on_audio_query.dart';

/// A folder represented only by songs already discovered by MediaStore.
class LocalMusicFolder {
  LocalMusicFolder({required this.path, required List<SongModel> songs})
    : songs = List.unmodifiable(songs);

  final String path;
  final List<SongModel> songs;

  String get name => path == '/' ? '/' : path.split('/').last;

  static List<LocalMusicFolder> groupSongs(Iterable<SongModel> songs) {
    final groups = <String, List<SongModel>>{};
    for (final song in songs) {
      final parent = parentPath(song.data);
      if (parent != null) {
        groups.putIfAbsent(parent, () => []).add(song);
      }
    }
    final folders = groups.entries.map((entry) {
      entry.value.sort((a, b) {
        final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        if (byTitle != 0) return byTitle;
        final byPath = a.data.compareTo(b.data);
        return byPath != 0 ? byPath : a.id.compareTo(b.id);
      });
      return LocalMusicFolder(path: entry.key, songs: entry.value);
    }).toList();
    folders.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.path.compareTo(b.path);
    });
    return List.unmodifiable(folders);
  }

  /// Uses Android/POSIX separators regardless of the host running this code.
  /// A content URI is not a filesystem path and cannot identify a real folder.
  static String? parentPath(String data) {
    var path = data;
    if (path.startsWith('file:')) {
      if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(path)) return null;
      try {
        final uri = Uri.parse(path);
        if (uri.host.isNotEmpty && uri.host != 'localhost') return null;
        path = uri.toFilePath(windows: false);
      } on FormatException {
        return null;
      } on UnsupportedError {
        return null;
      }
    }
    if (!path.startsWith('/') ||
        path.endsWith('/') ||
        path.contains('\u0000')) {
      return null;
    }
    final segments = path.split('/');
    if (segments.last == '.' || segments.last == '..') return null;
    final normalized = <String>[];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (normalized.isEmpty) return null;
        normalized.removeLast();
      } else {
        normalized.add(segment);
      }
    }
    if (normalized.isEmpty) return null;
    normalized.removeLast();
    return '/${normalized.join('/')}';
  }
}
