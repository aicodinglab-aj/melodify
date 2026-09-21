import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

enum LibraryStatus { idle, loading, ready, denied, failed }

/// One session collection shared by Local Music and Search.
class LocalMusicLibrary extends ChangeNotifier {
  LocalMusicLibrary({OnAudioQuery? query}) : _query = query ?? OnAudioQuery();
  final OnAudioQuery _query;
  LibraryStatus _status = LibraryStatus.idle;
  LibraryStatus get status => _status;
  List<SongModel> _songs = const [];
  List<SongModel> get songs => _songs;
  Future<void>? _pending;
  bool _disposed = false;

  Future<void> load({bool retry = false}) {
    if (_pending != null) return _pending!;
    if (!retry && status == LibraryStatus.ready) return Future.value();
    return _pending = _load().whenComplete(() => _pending = null);
  }

  Future<void> _load() async {
    _status = LibraryStatus.loading;
    _notify();
    try {
      var allowed = await _query.permissionsStatus();
      if (!allowed) allowed = await _query.permissionsRequest();
      if (!allowed) {
        _status = LibraryStatus.denied;
      } else {
        _songs = List.unmodifiable(
          await _query.querySongs(
            sortType: SongSortType.TITLE,
            orderType: OrderType.ASC_OR_SMALLER,
          ),
        );
        _status = LibraryStatus.ready;
      }
    } catch (_) {
      _status = LibraryStatus.failed;
    }
    _notify();
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

/// Rank metadata matches in memory without modifying the shared collection.
List<SongModel> searchLocalSongs(List<SongModel> songs, String query) {
  final term = query.trim().toLowerCase();
  if (term.isEmpty) return const [];

  int? rank(SongModel song) {
    final fields = [song.title, song.artist, song.album];
    for (var field = 0; field < fields.length; field++) {
      final text = fields[field]?.trim().toLowerCase();
      if (text == null || text.isEmpty || text == '<unknown>') continue;
      if (text == term) return field * 3;
      if (text.startsWith(term)) return field * 3 + 1;
      if (text.contains(term)) return field * 3 + 2;
    }
    return null;
  }

  final matches = <({SongModel song, int rank, String title, int index})>[];
  for (var index = 0; index < songs.length; index++) {
    final song = songs[index];
    final relevance = rank(song);
    if (relevance != null) {
      matches.add((
        song: song,
        rank: relevance,
        title: song.title.toLowerCase(),
        index: index,
      ));
    }
  }
  matches.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    final byTitle = a.title.compareTo(b.title);
    if (byTitle != 0) return byTitle;
    final byId = a.song.id.compareTo(b.song.id);
    if (byId != 0) return byId;
    final byPath = a.song.data.compareTo(b.song.data);
    return byPath != 0 ? byPath : a.index.compareTo(b.index);
  });
  return matches.map((match) => match.song).toList(growable: false);
}

/// MediaStore date_added order; unknown dates are omitted rather than invented.
List<SongModel> recentlyAddedSongs(List<SongModel> songs, {int count = 10}) {
  final dated = songs.where((song) => (song.dateAdded ?? 0) > 0).toList();
  dated.sort((a, b) {
    final byDate = b.dateAdded!.compareTo(a.dateAdded!);
    if (byDate != 0) return byDate;
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (byTitle != 0) return byTitle;
    final byId = a.id.compareTo(b.id);
    return byId != 0 ? byId : a.data.compareTo(b.data);
  });
  return dated.take(count).toList(growable: false);
}
