import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../library/favorites.dart';
import '../library/local_music_library.dart';
import '../library/playback_history.dart';
import '../library/playlists.dart';
import 'media_artwork.dart';
import 'notification_settings.dart';
import 'melodify_audio_handler.dart';
import 'playback_controller.dart';
import 'playback_interruptions.dart';
import 'startup_playback_restoration.dart';

/// Process/service lifetime, independent of Flutter widget mounting. The public
/// constructor also supports embedding with an existing controller/player.
class PlaybackRuntime {
  PlaybackRuntime({
    required this.controller,
    required this.history,
    required this.library,
    Favorites? favorites,
    Playlists? playlists,
    ArtworkResolver? artworkResolver,
  }) : favorites = favorites ?? Favorites(),
       playlists = playlists ?? Playlists() {
    handler = MelodifyAudioHandler(
      controller,
      artworkResolver: artworkResolver,
    );
    _notificationState = controller.player.playerStateStream.listen((state) {
      if (!state.playing) return;
      _notificationCheck?.cancel();
      _notificationCheck = Timer(
        const Duration(seconds: 1),
        notifications.refresh,
      );
    });
    restoration = StartupPlaybackRestoration(
      controller: controller,
      history: history,
      library: library,
    );
  }

  static Future<PlaybackRuntime>? _initialization;
  static Future<PlaybackRuntime> initialize() =>
      _initialization ??= _initialize();

  static Future<PlaybackRuntime> _initialize() async {
    final history = PlaybackHistory();
    final player = AudioPlayer(handleInterruptions: false);
    final runtime = PlaybackRuntime(
      controller: PlaybackController(player, history: history),
      history: history,
      library: LocalMusicLibrary(),
      artworkResolver: MediaArtwork().resolve,
    );
    runtime._serviceErrors = AudioService.asyncError.listen((error) {
      debugPrint("Melodify media service error: $error");
      runtime.backgroundIssue.value = 'System media controls encountered an error. Restart Melodify if controls remain unavailable.';
    });
    try {
      await AudioService.init<MelodifyAudioHandler>(
        builder: () => runtime.handler,
        config: const AudioServiceConfig(
          androidNotificationChannelId: NotificationSettings.channelId,
          androidNotificationChannelName: 'Music playback',
          androidNotificationChannelDescription:
              'Playback controls for Melodify music',
          androidNotificationClickStartsActivity: true,
          androidNotificationIcon: 'drawable/ic_stat_music',
          androidStopForegroundOnPause: false,
          androidResumeOnClick: false,
          artDownscaleWidth: 256,
          artDownscaleHeight: 256,
        ),
      );
    } catch (error, stack) {
      debugPrint(
        "Melodify media service initialization failed: $error\n$stack",
      );
      // Keep the existing player; never create a fallback/background player.
      runtime.backgroundIssue.value =
          'Background playback is unavailable. Restart Melodify to retry.';
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration.music().copyWith(
          androidWillPauseWhenDucked: true,
        ),
      );
      runtime._interruptions = PlaybackInterruptions(
        runtime.controller,
        interruptions: session.interruptionEventStream,
        becomingNoisy: session.becomingNoisyEventStream,
      );
    } catch (_) {
      runtime.backgroundIssue.value = 'Audio focus could not be configured. Restart Melodify before playing music.';
      runtime.controller.setPlaybackEnabled(false);
    }
    return runtime;
  }

  final PlaybackController controller;
  final PlaybackHistory history;
  final LocalMusicLibrary library;
  final Favorites favorites;
  final Playlists playlists;
  late final MelodifyAudioHandler handler;
  late final StartupPlaybackRestoration restoration;
  final notifications = NotificationSettings();
  StreamSubscription<PlayerState>? _notificationState;
  Timer? _notificationCheck;
  final backgroundIssue = ValueNotifier<String?>(null);
  PlaybackInterruptions? _interruptions;
  StreamSubscription<Object>? _serviceErrors;
  Future<void>? _start;
  bool _disposed = false;

  Future<void> start() => _start ??= Future.wait([
    favorites.restore(),
    playlists.restore(),
    restoration.start(),
  ]).then((_) {});

  /// Explicit runtime shutdown only; screen disposal/backgrounding never calls it.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    restoration.dispose();
    _notificationCheck?.cancel();
    await _notificationState?.cancel();
    notifications.dispose();
    await _interruptions?.dispose();
    await _serviceErrors?.cancel();
    await controller.close();
    await handler.dispose();
    controller.dispose();
    history.dispose();
    library.dispose();
    favorites.dispose();
    playlists.dispose();
    backgroundIssue.dispose();
  }
}
