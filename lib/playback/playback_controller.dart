import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import 'playback_queue.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController(this.player) {
    _stateSubscription = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          !_handlingCompletion &&
          queue.current != null) {
        _handlingCompletion = true;
        unawaited(_complete().whenComplete(() => _handlingCompletion = false));
      }
    });
  }

  final AudioPlayer player;
  final PlaybackQueue<SongModel> queue = PlaybackQueue<SongModel>();
  late final StreamSubscription<PlayerState> _stateSubscription;
  bool _handlingCompletion = false;
  int _generation = 0;

  SongModel? get currentSong => queue.current;
  int get currentIndex => queue.index;
  PlaybackMode get mode => queue.mode;
  String get title => currentSong?.title ?? '';
  String get artist {
    final value = currentSong?.artist?.trim();
    return value == null || value.isEmpty || value == '<unknown>'
        ? 'Local Music'
        : value;
  }

  Future<void> selectSong(List<SongModel> songs, SongModel song) async {
    final index = songs.indexWhere((item) => item.id == song.id);
    if (index < 0) throw StateError('Song is not in the displayed list.');
    queue.select(songs, index);
    notifyListeners();
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final song = currentSong;
    if (song == null) return;
    final generation = ++_generation;
    await player.stop();
    try {
      if (song.data.trim().isEmpty) throw StateError('No file path');
      await player.setFilePath(song.data);
    } catch (_) {
      final uri = song.uri;
      if (uri == null || uri.isEmpty) rethrow;
      await player.setUrl(uri);
    }
    if (generation == _generation) unawaited(player.play());
  }

  Future<void> togglePlayback() async {
    if (player.playing) {
      await player.pause();
    } else if (currentSong != null) {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      unawaited(player.play());
    }
  }

  Future<void> next() async {
    if (queue.next() != null) {
      notifyListeners();
      await _loadCurrent();
    }
  }

  Future<void> previous() async {
    if (currentSong == null) return;
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    queue.previous();
    notifyListeners();
    await _loadCurrent();
  }

  Future<void> _complete() async {
    final next = queue.next(automatic: true);
    if (next == null) {
      await player.stop();
    } else if (mode == PlaybackMode.repeatOne) {
      await player.seek(Duration.zero);
      unawaited(player.play());
    } else {
      notifyListeners();
      await _loadCurrent();
    }
  }

  void toggleShuffle() {
    queue.mode = mode == PlaybackMode.shuffle
        ? PlaybackMode.sequential
        : PlaybackMode.shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    queue.mode = switch (mode) {
      PlaybackMode.sequential || PlaybackMode.shuffle => PlaybackMode.repeatAll,
      PlaybackMode.repeatAll => PlaybackMode.repeatOne,
      PlaybackMode.repeatOne => PlaybackMode.sequential,
    };
    notifyListeners();
  }

  Future<void> close() async {
    ++_generation;
    await player.stop();
    queue.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    player.dispose();
    super.dispose();
  }
}
