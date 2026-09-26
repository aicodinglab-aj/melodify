import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/playback_history.dart';
import 'playback_controller.dart';
import 'playback_queue.dart';

typedef ArtworkResolver = Future<Uri?> Function(SongModel song);

/// A projection of the shared controller, never a second playback queue/engine.
class MelodifyAudioHandler extends BaseAudioHandler {
  MelodifyAudioHandler(this.controller, {this.artworkResolver}) {
    controller.addListener(_sync);
    _subscriptions = [
      controller.player.playerStateStream.listen((_) => _sync()),
      controller.player.playbackEventStream.listen(
        (_) => _sync(),
        onError: (Object _) {
          if (controller.sourceReady) controller.reportSystemError();
        },
      ),
      controller.player.durationStream.listen((_) => _sync()),
      controller.player.speedStream.listen((_) => _broadcast()),
    ];
    _sync();
  }

  final PlaybackController controller;
  final ArtworkResolver? artworkResolver;
  late final List<StreamSubscription<dynamic>> _subscriptions;
  String? _artKey;
  Uri? _artUri;
  bool _disposed = false;
  bool _presentationActive = false;

  static String? _metadata(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty || text.toLowerCase() == '<unknown>'
        ? null
        : text;
  }

  static MediaItem songMediaItem(
    SongModel song, {
    Uri? artUri,
    Duration? duration,
  }) => MediaItem(
    id: PlaybackHistory.keyFor(song),
    title: song.title,
    artist: _metadata(song.artist) ?? 'Local Music',
    album: _metadata(song.album),
    duration:
        duration ??
        (song.duration != null && song.duration! >= 0
            ? Duration(milliseconds: song.duration!)
            : null),
    artUri: artUri,
  );

  void _sync() {
    if (_disposed) return;
    final active = controller.playerVisible;
    final reopening = active && !_presentationActive;
    _presentationActive = active;
    final song = controller.currentSong;
    final key = song == null ? null : PlaybackHistory.keyFor(song);
    if (key != _artKey) {
      _artKey = key;
      _artUri = null;
      if (song != null && artworkResolver != null) {
        unawaited(_loadArtwork(song, key!));
      }
    }
    final items = controller.queue.items
        .map((item) {
          final current = identical(item, song);
          return songMediaItem(
            item,
            artUri: current ? _artUri : null,
            duration: current && controller.sourceReady
                ? controller.player.duration
                : null,
          );
        })
        .toList(growable: false);
    final previous = queue.value;
    // MediaItem equality is ID-based, so compare metadata explicitly.
    if (reopening ||
        previous.length != items.length ||
        List.generate(
          items.length,
          (i) => _sameItem(previous[i], items[i]),
        ).contains(false)) {
      queue.add(items);
    }
    final current = controller.currentIndex < 0
        ? null
        : items[controller.currentIndex];
    if (reopening || !_sameItem(mediaItem.value, current)) {
      mediaItem.add(current);
    }
    _broadcast();
  }

  bool _sameItem(MediaItem? a, MediaItem? b) =>
      a?.id == b?.id &&
      a?.title == b?.title &&
      a?.artist == b?.artist &&
      a?.album == b?.album &&
      a?.duration == b?.duration &&
      a?.artUri == b?.artUri;

  Future<void> _loadArtwork(SongModel song, String key) async {
    Uri? uri;
    try {
      uri = await artworkResolver!(song);
    } catch (_) {
      /* Metadata must never interrupt audio. */
    }
    if (_disposed || _artKey != key) return;
    _artUri = uri;
    _sync();
  }

  void _broadcast() {
    if (_disposed) return;
    final player = controller.player;
    final active = controller.playerVisible;
    final mode = controller.mode;
    final processing = !active
        ? AudioProcessingState.idle
        : controller.playbackError != null
        ? AudioProcessingState.error
        : !controller.sourceReady
        ? AudioProcessingState.loading
        : switch (player.processingState) {
            // A retained active source can be idle during native stop/reload.
            // Publishing session idle here tears down Android notification/service.
            audio.ProcessingState.idle => AudioProcessingState.ready,
            audio.ProcessingState.loading => AudioProcessingState.loading,
            audio.ProcessingState.buffering => AudioProcessingState.buffering,
            audio.ProcessingState.ready => AudioProcessingState.ready,
            audio.ProcessingState.completed => AudioProcessingState.completed,
          };
    playbackState.add(
      PlaybackState(
        controls: active
            ? [
                MediaControl.skipToPrevious,
                controller.sourceReady && player.playing
                    ? MediaControl.pause
                    : MediaControl.play,
                MediaControl.skipToNext,
                MediaControl.stop,
              ]
            : [],
        androidCompactActionIndices: active ? const [0, 1, 2] : const [],
        systemActions: active
            ? const {
                MediaAction.seek,
                MediaAction.setRepeatMode,
                MediaAction.setShuffleMode,
                MediaAction.skipToQueueItem,
              }
            : const {},
        processingState: processing,
        playing: active && controller.sourceReady && player.playing,
        updatePosition: active && controller.sourceReady
            ? player.position
            : Duration.zero,
        bufferedPosition: active && controller.sourceReady
            ? player.bufferedPosition
            : Duration.zero,
        speed: player.speed,
        queueIndex: active ? controller.currentIndex : null,
        repeatMode: switch (mode) {
          PlaybackMode.repeatOne => AudioServiceRepeatMode.one,
          PlaybackMode.repeatAll => AudioServiceRepeatMode.all,
          _ => AudioServiceRepeatMode.none,
        },
        shuffleMode: mode == PlaybackMode.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        errorCode: controller.playbackError == null ? null : 1,
        errorMessage: controller.playbackError,
      ),
    );
  }

  Future<void> _command(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      controller.reportSystemError();
    }
    _sync();
  }

  @override
  Future<void> play() => _command(controller.play);
  @override
  Future<void> pause() => _command(controller.pause);
  @override
  Future<void> stop() => _command(controller.hidePlayer);
  @override
  Future<void> seek(Duration position) =>
      _command(() => controller.seek(position));
  @override
  Future<void> skipToNext() => _command(controller.next);
  @override
  Future<void> skipToPrevious() => _command(controller.previous);
  @override
  Future<void> skipToQueueItem(int index) => _command(() async {
    final songs = controller.queue.items;
    if (index >= 0 && index < songs.length) {
      await controller.selectSong(songs, songs[index]);
    }
  });
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      if (controller.mode == PlaybackMode.shuffle) {
        controller.setMode(PlaybackMode.sequential);
      }
    } else {
      controller.setMode(PlaybackMode.shuffle);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    controller.setMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => PlaybackMode.repeatOne,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => PlaybackMode.repeatAll,
      AudioServiceRepeatMode.none => PlaybackMode.sequential,
    });
  }

  @override
  Future<void> onTaskRemoved() async {} // Removing the UI task is not Close.
  @override
  Future<void> onNotificationDeleted() => stop();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_sync);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await queue.close();
    await mediaItem.close();
    await playbackState.close();
    await queueTitle.close();
    await androidPlaybackInfo.close();
    await ratingStyle.close();
    await customEvent.close();
    await customState.close();
  }
}
