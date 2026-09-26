import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/playback_history.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_queue.dart';
import 'package:melodify/playback/startup_playback_restoration.dart';
import 'package:melodify/screens/home_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_v1_test.dart'
    show HomePlayer, HomeQuery, MemoryStore, song, flushEvents;

class RestoreStore extends MemoryStore {
  int writes = 0;
  Completer<List<String>>? gate;
  @override
  Future<List<String>> read() => gate?.future ?? super.read();
  @override
  Future<void> write(List<String> keys) async {
    writes++;
    await super.write(keys);
  }
}

class RestoreQuery extends HomeQuery {
  Completer<List<SongModel>>? gate;
  @override
  Future<List<SongModel>> querySongs({
    SongSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool? ignoreCase,
    String? path,
  }) => gate?.future ?? super.querySongs();
}

class RestorePlayer extends HomePlayer {
  int plays = 0;
  int pauses = 0;
  final attempted = <String>[];
  final badPaths = <String>{};
  final gates = <String, Completer<void>>{};
  Duration lastSeek = const Duration(seconds: 42);
  @override
  Duration get position => lastSeek;
  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    attempted.add(path);
    if (gates[path] != null) await gates[path]!.future;
    if (badPaths.contains(path)) throw StateError('missing file');
    return super.setFilePath(path);
  }

  @override
  Future<void> play() async {
    plays++;
    await super.play();
  }

  @override
  Future<void> pause() async {
    pauses++;
    await super.pause();
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    lastSeek = position ?? Duration.zero;
    await super.seek(position);
  }
}

class Rig {
  Rig({List<int> historyIds = const [2, 1]}) {
    store.data = historyIds
        .map((id) => PlaybackHistory.keyFor(song(id)))
        .toList();
    history = PlaybackHistory(store: store);
    library = LocalMusicLibrary(query: query);
    controller = PlaybackController(player, history: history);
    startup = StartupPlaybackRestoration(
      controller: controller,
      history: history,
      library: library,
    );
  }
  final store = RestoreStore();
  final query = RestoreQuery();
  final player = RestorePlayer();
  late final PlaybackHistory history;
  late final LocalMusicLibrary library;
  late final PlaybackController controller;
  late final StartupPlaybackRestoration startup;
  void dispose() {
    startup.dispose();
    controller.dispose();
    history.dispose();
    library.dispose();
  }
}

void main() {
  test('available recent history restores shared queue paused at index zero without history write', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.startup.start();
    await flushEvents();
    expect(rig.controller.queue.items.map((s) => s.id), [2, 1]);
    expect(rig.controller.currentIndex, 0);
    expect(rig.player.loaded, '/Music/2.mp3');
    expect(rig.player.playing, isFalse);
    expect(rig.player.processingState, ProcessingState.ready);
    expect(rig.player.plays, 0);
    expect(rig.player.lastSeek, Duration.zero);
    expect(rig.store.writes, 0);
    expect(rig.history.keys, rig.store.data);
    expect(identical(rig.controller.player, rig.player), isTrue);
  });

  testWidgets('Home Play observes and starts the restored shared track', (
    tester,
  ) async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
        home: Scaffold(
          body: HomeScreen(
            controller: rig.controller,
            library: rig.library,
            history: rig.history,
            onOpenLocalMusic: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Play',
            ),
          )
          .onPressed,
      isNull,
    );
    await rig.startup.start();
    await tester.pumpAndSettle();
    expect(rig.player.plays, 0);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Play',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(rig.player.plays, 1);
    expect(rig.player.playing, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(rig.store.writes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'missing newest identifier restores next available without pruning history',
    () async {
      final rig = Rig(historyIds: [99, 1, 2]);
      addTearDown(rig.dispose);
      await rig.startup.start();
      expect(rig.controller.queue.items.map((s) => s.id), [1, 2]);
      expect(rig.controller.currentIndex, 0);
      expect(rig.history.keys.first, 'path:/Music/99.mp3');
      expect(rig.store.writes, 0);
    },
  );

  for (final ids in [
    <int>[],
    [99, 98],
  ]) {
    test(
      'empty or entirely unavailable recent history $ids stays safe',
      () async {
        final rig = Rig(historyIds: ids);
        addTearDown(rig.dispose);
        await rig.startup.start();
        expect(rig.controller.currentSong, isNull);
        expect(rig.controller.currentIndex, -1);
        expect(rig.controller.queue.items, isEmpty);
        expect(rig.player.attempted, isEmpty);
        expect(rig.player.plays, 0);
      },
    );
  }

  test(
    'stale MediaStore file fails loading then restores the next recent track',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.player.badPaths.add('/Music/2.mp3');
      await rig.startup.start();
      expect(rig.player.attempted, ['/Music/2.mp3', '/Music/1.mp3']);
      expect(rig.controller.queue.items.map((s) => s.id), [1]);
      expect(rig.controller.currentIndex, 0);
      expect(rig.history.keys.length, 2);
      expect(rig.player.plays, 0);
      expect(rig.store.writes, 0);
    },
  );

  test('all cached sources fail without publishing an invalid queue', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    rig.player.badPaths.addAll(['/Music/1.mp3', '/Music/2.mp3']);
    await rig.startup.start();
    expect(rig.controller.queue.items, isEmpty);
    expect(rig.controller.currentIndex, -1);
    expect(rig.player.plays, 0);
    expect(rig.history.keys.length, 2);
  });

  test('existing active queue and mode are not replaced or paused', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.controller.selectSong([song(3), song(4)], song(4));
    rig.controller.toggleShuffle();
    final loads = rig.player.attempted.length;
    await rig.startup.start();
    expect(rig.controller.queue.items.map((s) => s.id), [3, 4]);
    expect(rig.controller.currentIndex, 1);
    expect(rig.controller.mode, PlaybackMode.shuffle);
    expect(rig.player.pauses, 0);
    expect(rig.player.attempted.length, loads);
    expect(rig.player.playing, isTrue);
  });

  for (final mode in PlaybackMode.values) {
    test('restoration preserves $mode', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.controller.queue.mode = mode;
      await rig.startup.start();
      expect(rig.controller.mode, mode);
      expect(rig.player.plays, 0);
    });
  }

  for (final historyFirst in [false, true]) {
    test(
      'waits for both history and library, historyFirst=$historyFirst',
      () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        rig.store.gate = Completer<List<String>>();
        rig.query.gate = Completer<List<SongModel>>();
        final start = rig.startup.start();
        if (historyFirst) {
          rig.store.gate!.complete(rig.store.data);
        } else {
          rig.query.gate!.complete([song(1), song(2)]);
        }
        await flushEvents();
        expect(rig.player.attempted, isEmpty);
        if (historyFirst) {
          rig.query.gate!.complete([song(1), song(2)]);
        } else {
          rig.store.gate!.complete(rig.store.data);
        }
        await start;
        expect(rig.controller.currentSong!.id, 2);
        await rig.startup.start();
        expect(rig.player.attempted.length, 1);
      },
    );
  }

  test(
    'permission retry can restore once availability becomes ready',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.query.allowed = false;
      await rig.startup.start();
      expect(rig.controller.currentSong, isNull);
      rig.query.allowed = true;
      await rig.library.load(retry: true);
      await flushEvents();
      expect(rig.controller.currentSong!.id, 2);
      expect(rig.player.plays, 0);
    },
  );

  test('user selection during delayed restoration wins without source overlap or autoplay', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    final gate = Completer<void>();
    rig.player.gates['/Music/2.mp3'] = gate;
    final start = rig.startup.start();
    await flushEvents();
    expect(rig.player.attempted, ['/Music/2.mp3']);
    expect(rig.controller.currentSong, isNull);
    final selection = rig.controller.selectSong([song(3)], song(3));
    await flushEvents();
    expect(rig.player.attempted, ['/Music/2.mp3']);
    gate.complete();
    await Future.wait([start, selection]);
    await flushEvents();
    expect(rig.player.loaded, '/Music/3.mp3');
    expect(rig.controller.currentSong!.id, 3);
    expect(rig.player.plays, 1);
    expect(rig.player.pauses, 0);
    expect(rig.history.keys.first, 'path:/Music/3.mp3');
  });

  test('explicit close during restoration cancels publication and later history changes do not restore again', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    final gate = Completer<void>();
    rig.player.gates['/Music/2.mp3'] = gate;
    final start = rig.startup.start();
    await flushEvents();
    final close = rig.controller.close();
    gate.complete();
    await Future.wait([start, close]);
    await rig.history.record(song(1));
    await rig.library.load(retry: true);
    await flushEvents();
    expect(rig.controller.currentSong, isNull);
    expect(rig.player.plays, 0);
    expect(rig.player.playing, isFalse);
  });

  test(
    'close before library readiness also prevents later startup resurrection',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.query.gate = Completer<List<SongModel>>();
      final start = rig.startup.start();
      await rig.controller.close();
      rig.query.gate!.complete([song(1), song(2)]);
      await start;
      expect(rig.controller.currentSong, isNull);
      expect(rig.player.attempted, isEmpty);
    },
  );

  test('restart restores from existing preferences without changing stored history', () async {
    SharedPreferences.setMockInitialValues({});
    final previous = PlaybackHistory();
    await previous.record(song(1));
    await previous.record(song(2));
    previous.dispose();
    final history = PlaybackHistory();
    final library = LocalMusicLibrary(query: HomeQuery());
    final player = RestorePlayer();
    final controller = PlaybackController(player, history: history);
    final startup = StartupPlaybackRestoration(
      controller: controller,
      history: history,
      library: library,
    );
    addTearDown(() {
      startup.dispose();
      controller.dispose();
      library.dispose();
      history.dispose();
    });
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getStringList(
      PreferencesPlaybackHistoryStore.preferenceKey,
    );
    await startup.start();
    await flushEvents();
    expect(controller.currentSong!.id, 2);
    expect(player.plays, 0);
    expect(
      prefs.getStringList(PreferencesPlaybackHistoryStore.preferenceKey),
      before,
    );
    await controller.togglePlayback();
    await flushEvents();
    expect(player.plays, 1);
    await controller.next();
    expect(controller.currentSong!.id, 1);
    player.lastSeek = Duration.zero;
    await controller.previous();
    expect(controller.currentSong!.id, 2);
  });

  test('production retains exactly one AudioPlayer construction', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(RegExp(r'\bAudioPlayer\s*\(').allMatches(source).length, 1);
  });
}
