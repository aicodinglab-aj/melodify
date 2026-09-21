import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import 'playback_queue.dart';
import '../library/playback_history.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController(this.player, {this.history}) {
    _stateSubscription = player.playerStateStream.listen((state) {
      if (state.playing && state.processingState == ProcessingState.ready) {
        final song = _pendingHistory;
        if (song != null && identical(song, currentSong)) {
          _pendingHistory = null;
          if (history != null) unawaited(history!.record(song));
        }
      }
      if (state.processingState == ProcessingState.completed &&
          !_handlingCompletion &&
          queue.current != null) {
        _handlingCompletion = true;
        unawaited(
          _complete()
              .catchError((Object error) {
                _reportPlaybackError();
              })
              .whenComplete(() => _handlingCompletion = false),
        );
      }
    });
  }

  final AudioPlayer player;
  final PlaybackHistory? history;
  SongModel? _loadedSong;
  SongModel? _pendingHistory;
  String? playbackError;
  bool _disposed = false;
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
    _loadedSong = null;
    _pendingHistory = null;
    playbackError = null;
    await player.stop();
    try {
      if (song.data.trim().isEmpty) throw StateError('No file path');
      await player.setFilePath(song.data);
    } catch (_) {
      final uri = song.uri;
      if (uri == null || uri.isEmpty) rethrow;
      await player.setUrl(uri);
    }
    if (generation == _generation) {
      _loadedSong = song;
      _startPlayback();
    }
  }

  void _startPlayback() {
    _pendingHistory = _loadedSong;
    final generation = _generation;
    unawaited(
      player.play().catchError((Object error) {
        if (_disposed || generation != _generation) return;
        _reportPlaybackError();
      }),
    );
  }

  void _reportPlaybackError() {
    if (_disposed) return;
    _pendingHistory = null;
    playbackError =
        'This song could not be played. It may no longer be available.';
    notifyListeners();
  }

  Future<void> _loadForTransport() async {
    try {
      await _loadCurrent();
    } catch (_) {
      _reportPlaybackError();
    }
  }

  Future<void> togglePlayback() async {
    if (player.playing) {
      await player.pause();
    } else if (currentSong != null) {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      _startPlayback();
    }
  }

  Future<void> next() async {
    if (queue.next() != null) {
      notifyListeners();
      await _loadForTransport();
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
    await _loadForTransport();
  }

  Future<void> _complete() async {
    final next = queue.next(automatic: true);
    if (next == null) {
      await player.stop();
    } else if (mode == PlaybackMode.repeatOne) {
      await player.seek(Duration.zero);
      _startPlayback();
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
    _loadedSong = null;
    _pendingHistory = null;
    playbackError = null;
    await player.stop();
    queue.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSubscription.cancel();
    player.dispose();
    super.dispose();
  }
}
