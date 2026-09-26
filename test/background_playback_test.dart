import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:melodify/library/favorites.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/playback_history.dart';
import 'package:melodify/library/playlists.dart';
import 'package:melodify/main.dart';
import 'package:melodify/playback/media_artwork.dart';
import 'package:melodify/playback/melodify_audio_handler.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_interruptions.dart';
import 'package:melodify/playback/playback_queue.dart';
import 'package:melodify/playback/playback_runtime.dart';
import 'package:melodify/playback/startup_playback_restoration.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_v1_test.dart' show song, HomeQuery, flushEvents;
import 'startup_playback_restoration_test.dart'
    show RestorePlayer, RestoreStore;
import 'favorites_test.dart' show Store;
import 'playlists_test.dart' show MemoryPlaylistsStore;

class SessionPlayer extends RestorePlayer {
  final events = StreamController<audio.PlaybackEvent>.broadcast();
  final durations = StreamController<Duration?>.broadcast();
  final speeds = StreamController<double>.broadcast();
  Duration? length = const Duration(minutes: 3);
  double rate = 1;
  bool disposed = false;
  @override
  Duration? get duration => length;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Duration get bufferedPosition => const Duration(seconds: 60);
  @override
  double get speed => rate;
  @override
  Stream<double> get speedStream => speeds.stream;
  @override
  Stream<audio.PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    await super.seek(position, index: index);
    events.add(
      audio.PlaybackEvent(
        processingState: processingState,
        updatePosition: lastSeek,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
    await durations.close();
    await speeds.close();
    await super.dispose();
  }
}

class BackgroundRig {
  BackgroundRig({ArtworkResolver? artwork, bool attach = true}) {
    history = PlaybackHistory(store: store);
    controller = PlaybackController(player, history: history);
    if (attach) {
      handler = MelodifyAudioHandler(controller, artworkResolver: artwork);
    }
  }
  final player = SessionPlayer()..lastSeek = Duration.zero;
  final store = RestoreStore();
  late final PlaybackHistory history;
  late final PlaybackController controller;
  late MelodifyAudioHandler handler;
  Future<void> select() =>
      controller.selectSong([song(1), song(2), song(3)], song(1));
  Future<void> dispose() async {
    await handler.dispose();
    controller.dispose();
    history.dispose();
  }
}

class ArtQuery extends Fake implements OnAudioQuery {
  Uint8List? bytes;
  bool fails = false;
  @override
  Future<Uint8List?> queryArtwork(
    int id,
    ArtworkType type, {
    ArtworkFormat? format,
    int? size,
    int? quality,
  }) async {
    expect(size, 256);
    if (fails) throw StateError('no artwork permission');
    return bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('handler wraps existing active controller without loading, autoplay or history writes', () async {
    final r = BackgroundRig(attach: false);
    await r.select();
    await flushEvents();
    await r.controller.pause();
    final plays = r.player.plays, writes = r.store.writes;
    r.handler = MelodifyAudioHandler(r.controller);
    addTearDown(r.dispose);
    await flushEvents();
    expect(identical(r.handler.controller.player, r.player), isTrue);
    expect(r.player.plays, plays);
    expect(r.store.writes, writes);
    expect(r.handler.queue.value.map((m) => m.id), [
      'path:/Music/1.mp3',
      'path:/Music/2.mp3',
      'path:/Music/3.mp3',
    ]);
    expect(r.handler.mediaItem.value!.id, 'path:/Music/1.mp3');
    expect(r.handler.playbackState.value.playing, isFalse);
  });

  test(
    'foreground state, metadata, duration and queue index synchronize',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await flushEvents();
      expect(r.handler.playbackState.value.playing, isTrue);
      expect(
        r.handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(r.handler.mediaItem.value!.duration, const Duration(minutes: 3));
      await r.controller.next();
      await flushEvents();
      expect(r.handler.playbackState.value.queueIndex, 1);
      expect(r.handler.mediaItem.value!.title, 'Song 2');
      r.player.length = const Duration(minutes: 4);
      r.player.durations.add(r.player.length);
      await flushEvents();
      expect(r.handler.mediaItem.value!.duration, const Duration(minutes: 4));
      expect(r.handler.queue.value[1].duration, const Duration(minutes: 4));
      r.player.rate = 1.25;
      r.player.speeds.add(1.25);
      await flushEvents();
      expect(r.handler.playbackState.value.speed, 1.25);
    },
  );

  test(
    'system Play/Pause are idempotent and use the existing player/history hook',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await flushEvents();
      await r.handler.pause();
      await flushEvents();
      expect(r.player.playing, isFalse);
      final plays = r.player.plays;
      await r.handler.play();
      await r.handler.play();
      await flushEvents();
      expect(r.player.plays, plays + 1);
      expect(r.handler.playbackState.value.playing, isTrue);
      expect(r.store.data.first, 'path:/Music/1.mp3');
    },
  );

  test(
    'system seeking clamps and updates position without feedback commands',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      final plays = r.player.plays;
      await r.handler.seek(const Duration(seconds: 27));
      await flushEvents();
      expect(r.player.lastSeek, const Duration(seconds: 27));
      expect(
        r.handler.playbackState.value.updatePosition,
        const Duration(seconds: 27),
      );
      expect(
        r.handler.playbackState.value.bufferedPosition,
        const Duration(seconds: 60),
      );
      await r.handler.seek(const Duration(minutes: 8));
      expect(r.player.lastSeek, const Duration(minutes: 3));
      expect(r.player.plays, plays);
    },
  );

  for (final seconds in [3, 4]) {
    test(
      'system Previous preserves $seconds-second restart boundary',
      () async {
        final r = BackgroundRig();
        addTearDown(r.dispose);
        await r.select();
        await r.handler.skipToNext();
        r.player.lastSeek = Duration(seconds: seconds);
        await r.handler.skipToPrevious();
        await flushEvents();
        expect(r.controller.currentIndex, seconds > 3 ? 1 : 0);
        if (seconds > 3) expect(r.player.lastSeek, Duration.zero);
      },
    );
  }

  test(
    'shuffle history and repeat state stay application-owned and exclusive',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await r.handler.setShuffleMode(AudioServiceShuffleMode.all);
      await r.handler.skipToNext();
      final next = r.controller.currentIndex;
      expect(next, isNot(0));
      r.player.lastSeek = Duration.zero;
      await r.handler.skipToPrevious();
      expect(r.controller.currentIndex, 0);
      await r.handler.skipToNext();
      expect(r.controller.currentIndex, next);
      expect(
        r.handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
      await r.handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(r.controller.mode, PlaybackMode.repeatOne);
      expect(
        r.handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
      r.controller.cycleRepeat();
      expect(
        r.handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.none,
      );
    },
  );

  test('Repeat One repeats completion but system Next advances', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    await r.handler.setRepeatMode(AudioServiceRepeatMode.one);
    r.player.emit(true, audio.ProcessingState.completed);
    await flushEvents();
    expect(r.controller.currentIndex, 0);
    expect(r.player.lastSeek, Duration.zero);
    await r.handler.skipToNext();
    expect(r.controller.currentIndex, 1);
  });

  test('Repeat All wraps system Next and Previous', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    await r.handler.setRepeatMode(AudioServiceRepeatMode.all);
    await r.handler.skipToQueueItem(2);
    await r.handler.skipToNext();
    expect(r.controller.currentIndex, 0);
    r.player.lastSeek = Duration.zero;
    await r.handler.skipToPrevious();
    expect(r.controller.currentIndex, 2);
  });

  test(
    'Sequential end stops naturally and manual Next stays at boundary',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await r.handler.skipToQueueItem(2);
      final plays = r.player.plays;
      await r.handler.skipToNext();
      expect(r.player.plays, plays);
      expect(r.controller.currentIndex, 2);
      r.player.emit(true, audio.ProcessingState.completed);
      await flushEvents();
      expect(r.player.playing, isFalse);
      expect(r.controller.wantsPlayback, isFalse);
      expect(r.controller.queue.items.length, 3);
    },
  );

  test('startup-restored paused track appears in media session without autoplay/history writes', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    r.store.data = ['path:/Music/2.mp3', 'path:/Music/1.mp3'];
    final library = LocalMusicLibrary(query: HomeQuery());
    final startup = StartupPlaybackRestoration(
      controller: r.controller,
      history: r.history,
      library: library,
    );
    addTearDown(() {
      startup.dispose();
      library.dispose();
    });
    await startup.start();
    await flushEvents();
    expect(r.handler.mediaItem.value!.id, 'path:/Music/2.mp3');
    expect(r.handler.playbackState.value.queueIndex, 0);
    expect(r.handler.playbackState.value.playing, isFalse);
    expect(r.player.plays, 0);
    expect(r.store.writes, 0);
    await r.handler.play();
    await flushEvents();
    expect(r.player.plays, 1);
    expect(r.store.writes, 1);
  });

  test(
    'system Close during delayed restoration wins and clears all media state',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      final gate = Completer<void>();
      r.player.gates['/Music/1.mp3'] = gate;
      final restoring = r.controller.restoreRecentSongs([song(1)]);
      await flushEvents();
      final closing = r.handler.stop();
      gate.complete();
      await Future.wait([restoring, closing]);
      await flushEvents();
      expect(r.controller.currentSong, isNull);
      expect(r.handler.mediaItem.value, isNull);
      expect(r.handler.queue.value, isEmpty);
      expect(
        r.handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(r.player.plays, 0);
      await r.controller.restoreRecentSongs([song(1)]);
      expect(r.controller.currentSong, isNull);
    },
  );

  test('task removal keeps playback, notification dismissal pauses and retains queue', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    await r.handler.onTaskRemoved();
    expect(r.player.playing, isTrue);
    expect(r.controller.queue.items.length, 3);
    await r.handler.onNotificationDeleted();
    await flushEvents();
    expect(r.player.playing, isFalse);
    expect(r.handler.queue.value.length, 3);
    expect(r.controller.playerVisible, isFalse);
    expect(
      r.handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  for (final type in AudioInterruptionType.values) {
    test('interruption $type pauses and only resumable types resume', () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      final policy = PlaybackInterruptions(
        r.controller,
        interruptions: const Stream.empty(),
        becomingNoisy: const Stream.empty(),
      );
      addTearDown(policy.dispose);
      await policy.handle(AudioInterruptionEvent(true, type));
      expect(r.player.playing, isFalse);
      await policy.handle(AudioInterruptionEvent(false, type));
      expect(r.player.playing, type != AudioInterruptionType.unknown);
    });
  }

  test('a newer interruption invalidates a pending resume', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    final policy = PlaybackInterruptions(
      r.controller,
      interruptions: const Stream.empty(),
      becomingNoisy: const Stream.empty(),
    );
    addTearDown(policy.dispose);
    await policy.handle(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    final ending = policy.handle(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    final newer = policy.handle(
      AudioInterruptionEvent(true, AudioInterruptionType.unknown),
    );
    await Future.wait([ending, newer]);
    expect(r.player.playing, isFalse);
    expect(r.player.plays, 1);
  });

  for (final action in ['pause', 'close', 'disconnect', 'next']) {
    test(
      '$action during interruption prevents late automatic resume',
      () async {
        final r = BackgroundRig();
        addTearDown(r.dispose);
        await r.select();
        final policy = PlaybackInterruptions(
          r.controller,
          interruptions: const Stream.empty(),
          becomingNoisy: const Stream.empty(),
        );
        addTearDown(policy.dispose);
        await policy.handle(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        switch (action) {
          case 'pause':
            await r.handler.pause();
          case 'close':
            await r.handler.stop();
          case 'disconnect':
            await policy.disconnect();
          case 'next':
            await r.handler.skipToNext();
            await r.handler.pause();
        }
        final plays = r.player.plays;
        await policy.handle(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        expect(r.player.plays, plays);
        expect(r.player.playing, isFalse);
      },
    );
  }

  test(
    'headset disconnect stream pauses once and cancelled listeners stay silent',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      final noisy = StreamController<void>.broadcast();
      final interruptions =
          StreamController<AudioInterruptionEvent>.broadcast();
      final policy = PlaybackInterruptions(
        r.controller,
        interruptions: interruptions.stream,
        becomingNoisy: noisy.stream,
      );
      noisy.add(null);
      await flushEvents();
      expect(r.player.pauses, 1);
      expect(r.player.playing, isFalse);
      await policy.dispose();
      await r.handler.play();
      noisy.add(null);
      await flushEvents();
      expect(r.player.playing, isTrue);
      await noisy.close();
      await interruptions.close();
    },
  );

  test('Pause during source loading suppresses completion autoplay', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    final gate = Completer<void>();
    r.player.gates['/Music/1.mp3'] = gate;
    final selection = r.select();
    await flushEvents();
    await r.handler.pause();
    gate.complete();
    await selection;
    await flushEvents();
    expect(r.player.plays, 0);
    expect(r.handler.playbackState.value.playing, isFalse);
    await r.handler.play();
    expect(r.player.plays, 1);
  });

  test(
    'missing next song publishes safe error without replacing queue/history',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await flushEvents();
      final history = List.of(r.store.data);
      r.player.badPaths.add('/Music/2.mp3');
      await r.handler.skipToNext();
      await flushEvents();
      expect(
        r.handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      expect(r.handler.playbackState.value.playing, isFalse);
      expect(r.controller.queue.items.length, 3);
      expect(r.store.data, history);
    },
  );

  test(
    'metadata mapping uses stable identity and safe missing artist/album',
    () {
      final s = SongModel({
        '_id': 9,
        '_data': '/Music/9.mp3',
        'title': 'Title',
        'artist': '<unknown>',
        'album': 'Album',
        'duration': 12345,
      });
      final item = MelodifyAudioHandler.songMediaItem(s);
      expect(item.id, PlaybackHistory.keyFor(s));
      expect(item.artist, 'Local Music');
      expect(item.album, 'Album');
      expect(item.duration, const Duration(milliseconds: 12345));
      expect(item.artUri, isNull);
    },
  );

  test('artwork failure and late artwork never affect playback or new current item', () async {
    final art = Completer<Uri?>();
    final r = BackgroundRig(
      artwork: (s) =>
          s.id == 1 ? art.future : Future.error(StateError('missing art')),
    );
    addTearDown(r.dispose);
    await r.select();
    await r.handler.skipToNext();
    await flushEvents();
    art.complete(Uri.file('/obsolete.jpg'));
    await flushEvents();
    expect(r.handler.mediaItem.value!.id, 'path:/Music/2.mp3');
    expect(r.handler.mediaItem.value!.artUri, isNull);
    expect(r.player.playing, isTrue);
    expect(r.controller.playbackError, isNull);
  });

  test('thumbnail resolver tolerates missing, invalid, oversized and inaccessible artwork', () async {
    final query = ArtQuery();
    final resolver = MediaArtwork(query: query);
    expect(await resolver.resolve(song(1)), isNull);
    query.bytes = Uint8List.fromList([1, 2, 3]);
    expect(await resolver.resolve(song(2)), isNull);
    query.bytes = Uint8List(600 * 1024);
    expect(await resolver.resolve(song(3)), isNull);
    query.fails = true;
    expect(await resolver.resolve(song(4)), isNull);
  });

  test('valid artwork uses bounded local files and regenerates a deleted thumbnail', () async {
    final root = await Directory.systemTemp.createTemp('melodify-art-test-');
    addTearDown(() => root.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final query = ArtQuery()..bytes = bytes!.buffer.asUint8List();
    final resolver = MediaArtwork(query: query, directory: () async => root);
    final first = await resolver.resolve(song(1));
    expect(first, isNotNull);
    expect(await File.fromUri(first!).exists(), isTrue);
    expect(await resolver.resolve(song(1)), first);
    await File.fromUri(first).delete();
    final replacement = await resolver.resolve(song(1));
    expect(replacement, isNotNull);
    expect(await File.fromUri(replacement!).exists(), isTrue);
    for (var id = 2; id <= 19; id++) {
      expect(await resolver.resolve(song(id)), isNotNull);
    }
    final files = await Directory('${root.path}/melodify_media_artwork')
        .list()
        .toList();
    expect(files.length, 16);
  });

  test(
    'state events do not feed back into player commands or history',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await flushEvents();
      final plays = r.player.plays, writes = r.store.writes;
      for (var i = 0; i < 20; i++) {
        r.player.events.add(
          audio.PlaybackEvent(processingState: audio.ProcessingState.ready),
        );
      }
      await flushEvents();
      expect(r.player.plays, plays);
      expect(r.store.writes, writes);
      await r.handler.dispose();
      r.player.emit(false, audio.ProcessingState.ready);
      await flushEvents();
      // dispose is idempotent, so the rig can perform normal teardown too.
    },
  );

  for (final source in ['favorites', 'playlist']) {
    test('$source ordered playback stays the system queue', () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      final songs = [song(1), song(2), song(3)];
      List<SongModel> queue;
      if (source == 'favorites') {
        final favorites = Favorites(store: Store());
        addTearDown(favorites.dispose);
        await favorites.like(song(1));
        await favorites.like(song(3));
        queue = favorites.resolve(songs);
      } else {
        final playlists = Playlists(store: MemoryPlaylistsStore());
        addTearDown(playlists.dispose);
        final p = await playlists.create('Mix');
        await playlists.addSongs(p.id, [song(3), song(1)]);
        queue = playlists.resolve(p.id, songs);
      }
      await r.controller.selectSong(queue, queue[1]);
      await flushEvents();
      expect(r.handler.queue.value.map((s) => s.id), [
        'path:/Music/3.mp3',
        'path:/Music/1.mp3',
      ]);
      expect(r.handler.playbackState.value.queueIndex, 1);
    });
  }

  testWidgets(
    'widget removal, background lifecycle and reattachment keep one runtime/player',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      late SessionPlayer player;
      final runtime = (await tester.runAsync(() async {
        final history = PlaybackHistory(store: RestoreStore());
        player = SessionPlayer();
        return PlaybackRuntime(
          controller: PlaybackController(player, history: history),
          history: history,
          library: LocalMusicLibrary(query: HomeQuery()),
        );
      }))!;
      await tester.pumpWidget(MelodifyApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => runtime.controller.selectSong(
          runtime.library.songs,
          runtime.library.songs.first,
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(player.playing, isTrue);
      await runtime.handler.onTaskRemoved();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(player.disposed, isFalse);
      expect(player.playing, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(MelodifyApp(runtime: runtime));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close player'), findsOneWidget);
      expect(player.plays, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(runtime.dispose);
    },
  );

  test(
    'single-player/service registration and Android/iOS static contract',
    () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final source = files.map((f) => f.readAsStringSync()).join('\n');
      expect(RegExp(r'\bAudioPlayer\s*\(').allMatches(source).length, 1);
      expect(RegExp(r'AudioService\.init<').allMatches(source).length, 1);
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      for (final part in [
        'FOREGROUND_SERVICE_MEDIA_PLAYBACK',
        'WAKE_LOCK',
        'android:foregroundServiceType="mediaPlayback"',
        'MediaButtonReceiver',
      ]) {
        expect(manifest, contains(part));
      }
      expect(
        File('android/app/src/main/kotlin/com/example/melodify/MainActivity.kt')
            .readAsStringSync(),
        contains('MainActivity : AudioServiceActivity()'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('UIBackgroundModes'),
      );
    },
  );
}
