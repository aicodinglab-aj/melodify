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
  Future<void> _sourceOperations = Future.value();
  Future<void>? _startupRestoration;
  int _userActionRevision = 0;
  bool _wantsPlayback = false;
  bool _playbackEnabled = true;
  void setPlaybackEnabled(bool enabled) {
    _playbackEnabled = enabled;
  }

  int get userActionRevision => _userActionRevision;
  bool get wantsPlayback => _wantsPlayback;
  bool get sourceReady =>
      currentSong != null && identical(_loadedSong, currentSong);

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
    _userActionRevision++;
    _wantsPlayback = true;
    queue.select(songs, index);
    notifyListeners();
    await _loadCurrent();
  }

  // Serialize native source changes: a slow startup preload must finish before
  // a newer user selection replaces it on the same player.
  Future<void> _withSourceLock(Future<void> Function() action) {
    final operation = _sourceOperations.then((_) => action());
    _sourceOperations = operation.catchError((Object _) {});
    return operation;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _loadCurrent() {
    final song = currentSong;
    if (song == null) return Future.value();
    final generation = ++_generation;
    _loadedSong = null;
    _pendingHistory = null;
    playbackError = null;
    return _withSourceLock(() async {
      if (!_isCurrent(generation)) return;
      try {
        await player.stop();
        if (!_isCurrent(generation)) return;
        await _loadSource(song);
      } catch (_) {
        if (_isCurrent(generation)) {
          _reportPlaybackError();
          rethrow;
        }
        return;
      }
      if (_isCurrent(generation)) {
        _loadedSong = song;
        if (_wantsPlayback) _startPlayback();
        notifyListeners();
      }
    });
  }

  Future<void> _loadSource(SongModel song) async {
    try {
      if (song.data.trim().isEmpty) throw StateError('No file path');
      await player.setFilePath(song.data);
    } catch (_) {
      final uri = song.uri;
      if (uri == null || uri.isEmpty) rethrow;
      await player.setUrl(uri);
    }
  }

  /// Restores a recent queue once, without autoplay or a history write. Resolve
  /// identifiers against a ready local library before calling this method.
  Future<void> restoreRecentSongs(List<SongModel> songs) =>
      _startupRestoration ??= _restoreRecentSongs(List.of(songs));

  Future<void> _restoreRecentSongs(List<SongModel> songs) async {
    // Any explicit selection/close wins, even if it happened before discovery.
    if (_disposed || currentSong != null || _generation != 0 || songs.isEmpty) {
      return;
    }
    final generation = ++_generation;
    await _withSourceLock(() async {
      for (var index = 0; index < songs.length; index++) {
        if (!_isCurrent(generation) || currentSong != null) return;
        final song = songs[index];
        try {
          await player.stop();
          if (!_isCurrent(generation)) return;
          await _loadSource(song);
          if (!_isCurrent(generation)) return;
          await player.pause();
          await player.seek(Duration.zero);
        } catch (_) {
          // A stale MediaStore entry may no longer load. Keep its persisted key
          // and try the next recent song; never publish a failed current track.
          continue;
        }
        if (!_isCurrent(generation) || currentSong != null) return;
        _loadedSong = song;
        _pendingHistory = null;
        playbackError = null;
        queue.select(songs.sublist(index), 0);
        notifyListeners();
        return;
      }
    });
  }

  void _startPlayback() {
    if (!_playbackEnabled || !_wantsPlayback || !sourceReady) return;
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
    _wantsPlayback = false;
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

  Future<void> togglePlayback() => player.playing ? pause() : play();

  Future<void> play({bool userInitiated = true}) async {
    if (userInitiated) _userActionRevision++;
    if (currentSong == null) return;
    _wantsPlayback = true;
    if (!sourceReady || player.playing) return;
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    _startPlayback();
  }

  Future<void> pause({bool userInitiated = true}) async {
    if (userInitiated) _userActionRevision++;
    _wantsPlayback = false;
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    if (!sourceReady) return;
    final duration = player.duration;
    final max = duration?.inMilliseconds ?? position.inMilliseconds;
    await player.seek(
      Duration(
        milliseconds: position.inMilliseconds.clamp(0, max < 0 ? 0 : max),
      ),
    );
  }

  void setMode(PlaybackMode value) {
    queue.mode = value;
    notifyListeners();
  }

  void reportSystemError() => _reportPlaybackError();

  Future<void> next() async {
    _userActionRevision++;
    if (queue.next() != null) {
      _wantsPlayback = true;
      notifyListeners();
      await _loadForTransport();
    }
  }

  Future<void> previous() async {
    _userActionRevision++;
    if (currentSong == null) return;
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    _wantsPlayback = true;
    queue.previous();
    notifyListeners();
    await _loadForTransport();
  }

  Future<void> _complete() async {
    final next = queue.next(automatic: true);
    if (next == null) {
      _wantsPlayback = false;
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
    _userActionRevision++;
    _wantsPlayback = false;
    ++_generation;
    _loadedSong = null;
    _pendingHistory = null;
    playbackError = null;
    queue.clear();
    notifyListeners();
    await _withSourceLock(() async {
      if (!_disposed) await player.stop();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSubscription.cancel();
    player.dispose();
    super.dispose();
  }
}
