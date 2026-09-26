import 'dart:async';

import '../library/local_music_library.dart';
import '../library/playback_history.dart';
import 'playback_controller.dart';

/// Runtime-owned startup coordination, independent of Home rendering/navigation.
/// Permission/query retries may supply availability later in the same session.
class StartupPlaybackRestoration {
  StartupPlaybackRestoration({
    required this.controller,
    required this.history,
    required this.library,
  });

  final PlaybackController controller;
  final PlaybackHistory history;
  final LocalMusicLibrary library;
  Future<void>? _startFuture;
  Future<void>? _attempt;
  bool _disposed = false;

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_disposed) return;
    history.addListener(_onChanged);
    library.addListener(_onChanged);
    await Future.wait([history.restore(), library.load()]);
    await _tryRestore();
  }

  void _onChanged() => unawaited(_tryRestore());

  Future<void> _tryRestore() {
    if (_disposed) return Future.value();
    if (_attempt != null) return _attempt!;
    if (!history.restored || library.status != LibraryStatus.ready) {
      return Future.value();
    }
    return _attempt = controller.restoreRecentSongs(
      history.resolve(library.songs, count: PlaybackHistory.limit),
    );
  }

  void dispose() {
    _disposed = true;
    if (_startFuture != null) {
      history.removeListener(_onChanged);
      library.removeListener(_onChanged);
    }
  }
}
