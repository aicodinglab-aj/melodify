import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/playback_history.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/screens/home_screen.dart';
import 'package:melodify/screens/local_music_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

SongModel song(int id, {int? added, String? title}) => SongModel({
  '_id': id,
  '_data': '/Music/$id.mp3',
  'title': title ?? 'Song $id',
  'artist': 'Artist',
  'date_added': added,
});

class MemoryStore implements PlaybackHistoryStore {
  List<String> data = [];
  bool fail = false;
  @override
  Future<List<String>> read() async {
    if (fail) throw StateError('storage unavailable');
    return List.of(data);
  }

  @override
  Future<void> write(List<String> keys) async {
    if (fail) throw StateError('storage unavailable');
    data = List.of(keys);
  }
}

class HomeQuery extends Fake implements OnAudioQuery {
  List<SongModel> songs = [song(1, added: 100), song(2, added: 200)];
  int calls = 0;
  bool allowed = true;
  bool fail = false;
  @override
  Future<bool> permissionsStatus() async => allowed;
  @override
  Future<bool> permissionsRequest({bool retryRequest = false}) async => allowed;
  @override
  Future<List<SongModel>> querySongs({
    SongSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool? ignoreCase,
    String? path,
  }) async {
    calls++;
    if (fail) throw StateError('query failed');
    return songs;
  }
}

class HomePlayer extends Fake implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast();
  PlayerState state = PlayerState(false, ProcessingState.idle);
  String? loaded;
  bool failLoad = false;
  bool failPlay = false;
  bool readyOnPlay = true;
  void emit(bool playing, ProcessingState processing) {
    state = PlayerState(playing, processing);
    states.add(state);
  }

  @override
  PlayerState get playerState => state;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<bool> get playingStream => states.stream.map((s) => s.playing);
  @override
  bool get playing => state.playing;
  @override
  ProcessingState get processingState => state.processingState;
  @override
  Duration get position => Duration.zero;
  @override
  AudioSource? get audioSource => null;
  @override
  Future<void> stop() async => emit(false, ProcessingState.idle);
  @override
  Future<void> pause() async => emit(false, ProcessingState.ready);
  @override
  Future<void> seek(Duration? position, {int? index}) async =>
      emit(playing, ProcessingState.ready);
  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    if (failLoad) throw StateError('deleted file');
    loaded = path;
    emit(false, ProcessingState.ready);
    return const Duration(minutes: 2);
  }

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('decoder failure');
    emit(true, readyOnPlay ? ProcessingState.ready : ProcessingState.loading);
  }

  @override
  Future<void> dispose() async => states.close();
}

Future<void> flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test(
    'new plays are newest first and replays move to top without duplicates',
    () async {
      final history = PlaybackHistory(store: MemoryStore());
      addTearDown(history.dispose);
      await history.record(song(1));
      expect(history.resolve([song(1)]).single.id, 1);
      await history.record(song(2));
      expect(history.resolve([song(1), song(2)]).map((s) => s.id), [2, 1]);
      await history.record(song(1));
      await history.record(song(1));
      expect(history.resolve([song(1), song(2)]).map((s) => s.id), [1, 2]);
    },
  );

  test(
    'history retains at most 50 identifiers and Home resolves at most 10',
    () async {
      final store = MemoryStore();
      final history = PlaybackHistory(store: store);
      addTearDown(history.dispose);
      final songs = List.generate(55, (id) => song(id));
      for (final item in songs) {
        await history.record(item);
      }
      expect(history.keys.length, 50);
      expect(store.data.length, 50);
      expect(
        history.resolve(songs).map((s) => s.id),
        List.generate(10, (i) => 54 - i),
      );
      expect(history.keys.contains(PlaybackHistory.keyFor(song(0))), isFalse);
    },
  );

  test('SharedPreferences history survives a new history instance', () async {
    SharedPreferences.setMockInitialValues({});
    final first = PlaybackHistory();
    await first.record(song(1));
    await first.record(song(2));
    final second = PlaybackHistory();
    await second.restore();
    expect(second.resolve([song(1), song(2)]).map((s) => s.id), [2, 1]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PreferencesPlaybackHistoryStore.preferenceKey), [
      'path:/Music/2.mp3',
      'path:/Music/1.mp3',
    ]);
    first.dispose();
    second.dispose();
  });

  test(
    'unavailable history entries are omitted and fresh metadata is resolved',
    () async {
      final history = PlaybackHistory(store: MemoryStore());
      addTearDown(history.dispose);
      await history.record(song(1));
      await history.record(song(2));
      final renamed = song(1, title: 'Updated title');
      expect(history.resolve([renamed]).single.title, 'Updated title');
      expect(history.resolve([]), isEmpty);
      expect(history.keys.length, 2);
    },
  );

  test('storage failures retain session history without throwing', () async {
    final history = PlaybackHistory(store: MemoryStore()..fail = true);
    addTearDown(history.dispose);
    await history.record(song(1));
    expect(history.storageAvailable, isFalse);
    expect(history.resolve([song(1)]).single.id, 1);
  });

  test(
    'concurrent records preserve event order through restoration and saving',
    () async {
      final store = MemoryStore()..data = ['path:/Music/3.mp3'];
      final history = PlaybackHistory(store: store);
      addTearDown(history.dispose);
      await Future.wait([history.record(song(1)), history.record(song(2))]);
      expect(store.data, [
        'path:/Music/2.mp3',
        'path:/Music/1.mp3',
        'path:/Music/3.mp3',
      ]);
    },
  );

  test(
    'Recently Added uses valid dates descending with deterministic ties',
    () {
      final songs = [
        song(1),
        song(2, added: 0),
        song(3, added: -1),
        song(4, added: 100, title: 'z'),
        song(5, added: 200),
        song(6, added: 100, title: 'Alpha'),
      ];
      expect(recentlyAddedSongs(songs).map((s) => s.id), [5, 6, 4]);
      expect(songs.map((s) => s.id), [1, 2, 3, 4, 5, 6]);
      expect(
        recentlyAddedSongs(List.generate(20, (i) => song(i, added: i + 1)))
            .length,
        10,
      );
    },
  );

  test(
    'history records only ready playing sources, including automatic next',
    () async {
      final history = PlaybackHistory(store: MemoryStore());
      final player = HomePlayer()..readyOnPlay = false;
      final controller = PlaybackController(player, history: history);
      addTearDown(controller.dispose);
      addTearDown(history.dispose);
      await controller.selectSong([song(1), song(2)], song(1));
      await flushEvents();
      expect(history.keys, isEmpty);
      player.emit(true, ProcessingState.ready);
      await flushEvents();
      expect(history.resolve([song(1), song(2)]).map((s) => s.id), [1]);
      player.readyOnPlay = true;
      player.emit(true, ProcessingState.completed);
      await flushEvents();
      expect(controller.currentIndex, 1);
      expect(history.resolve([song(1), song(2)]).map((s) => s.id), [2, 1]);
      await controller.previous();
      await flushEvents();
      expect(history.resolve([song(1), song(2)]).map((s) => s.id), [1, 2]);
    },
  );

  test('failed source loading and play errors do not add history', () async {
    final history = PlaybackHistory(store: MemoryStore());
    final player = HomePlayer()..failLoad = true;
    final controller = PlaybackController(player, history: history);
    addTearDown(controller.dispose);
    addTearDown(history.dispose);
    await expectLater(
      controller.selectSong([song(1)], song(1)),
      throwsStateError,
    );
    player.failLoad = false;
    player.failPlay = true;
    await controller.selectSong([song(1)], song(1));
    await flushEvents();
    expect(history.keys, isEmpty);
    expect(controller.playbackError, isNotNull);
  });

  test(
    'deleted queue entries fail safely on manual and automatic next',
    () async {
      final history = PlaybackHistory(store: MemoryStore());
      final player = HomePlayer();
      final controller = PlaybackController(player, history: history);
      addTearDown(controller.dispose);
      addTearDown(history.dispose);
      for (final automatic in [false, true]) {
        player.failLoad = false;
        await controller.selectSong([song(1), song(2)], song(1));
        await flushEvents();
        player.failLoad = true;
        if (automatic) {
          player.emit(true, ProcessingState.completed);
          await flushEvents();
        } else {
          await controller.next();
        }
        expect(controller.playbackError, isNotNull);
        expect(controller.currentIndex, 1);
        expect(history.resolve([song(1), song(2)]).map((s) => s.id), [1]);
      }
    },
  );

  test(
    'repeat one and pause resume preserve history uniqueness and queue',
    () async {
      final history = PlaybackHistory(store: MemoryStore());
      final player = HomePlayer();
      final controller = PlaybackController(player, history: history);
      addTearDown(controller.dispose);
      addTearDown(history.dispose);
      await controller.selectSong([song(1), song(2)], song(1));
      await flushEvents();
      controller.cycleRepeat();
      controller.cycleRepeat();
      player.emit(true, ProcessingState.completed);
      await flushEvents();
      expect(controller.currentIndex, 0);
      await controller.togglePlayback();
      await controller.togglePlayback();
      await flushEvents();
      expect(history.keys, ['path:/Music/1.mp3']);
      expect(controller.queue.items.map((s) => s.id), [1, 2]);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    LocalMusicLibrary library,
    PlaybackHistory history,
    PlaybackController controller, {
    MelodifyThemeId theme = MelodifyThemeId.melodifyGreen,
    ValueChanged<bool>? open,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.forId(theme),
        home: Scaffold(
          body: HomeScreen(
            controller: controller,
            library: library,
            history: history,
            onOpenLocalMusic: open ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final section in ['recently-played', 'recently-added']) {
    testWidgets(
      '$section selection snapshots displayed queue and correct index',
      (tester) async {
        final query = HomeQuery();
        final library = LocalMusicLibrary(query: query);
        final history = PlaybackHistory(store: MemoryStore());
        final player = HomePlayer();
        final controller = PlaybackController(player, history: history);
        addTearDown(controller.dispose);
        addTearDown(history.dispose);
        addTearDown(library.dispose);
        await history.record(song(1));
        await history.record(song(2));
        await mount(tester, library, history, controller);
        final target = find.byKey(ValueKey('$section-1'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(controller.queue.items.map((s) => s.id), [2, 1]);
        expect(controller.currentIndex, 1);
        expect(player.loaded, '/Music/1.mp3');
        expect(history.resolve(library.songs).map((s) => s.id), [1, 2]);
        await controller.previous();
        expect(controller.currentSong!.id, 2);
        await controller.next();
        expect(controller.currentSong!.id, 1);
        expect(query.calls, 1);
      },
    );
  }

  testWidgets('stale deleted file shows an error and does not enter history', (
    tester,
  ) async {
    final library = LocalMusicLibrary(query: HomeQuery());
    final history = PlaybackHistory(store: MemoryStore());
    final controller = PlaybackController(
      HomePlayer()..failLoad = true,
      history: history,
    );
    addTearDown(controller.dispose);
    addTearDown(history.dispose);
    addTearDown(library.dispose);
    await mount(tester, library, history, controller);
    final target = find.byKey(const ValueKey('recently-added-2'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The file may no longer be available.'),
      findsOneWidget,
    );
    expect(history.keys, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Quick Access delegates to existing Local Music with chosen view',
    (tester) async {
      final library = LocalMusicLibrary(query: HomeQuery());
      final history = PlaybackHistory(store: MemoryStore());
      final controller = PlaybackController(HomePlayer(), history: history);
      addTearDown(controller.dispose);
      addTearDown(history.dispose);
      addTearDown(library.dispose);
      final modes = <bool>[];
      await mount(tester, library, history, controller, open: modes.add);
      for (final label in ['Local Music', 'Songs', 'Folders']) {
        await tester.tap(find.widgetWithText(ActionChip, label));
      }
      expect(modes, [false, false, true]);
      await tester.pumpWidget(
        MaterialApp(
          theme: MelodifyTheme.dark,
          home: LocalMusicScreen(
            controller: controller,
            library: library,
            initialShowFolders: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Music'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Folders'))
            .selected,
        isTrue,
      );
    },
  );

  for (final status in ['empty', 'denied', 'failed']) {
    testWidgets('Home handles $status local library', (tester) async {
      final query = HomeQuery();
      if (status == 'empty') query.songs = [];
      if (status == 'denied') query.allowed = false;
      if (status == 'failed') query.fail = true;
      final library = LocalMusicLibrary(query: query);
      final history = PlaybackHistory(store: MemoryStore());
      final controller = PlaybackController(HomePlayer(), history: history);
      addTearDown(controller.dispose);
      addTearDown(history.dispose);
      addTearDown(library.dispose);
      await mount(tester, library, history, controller);
      if (status == 'empty') {
        expect(
          find.text('No local songs were found on this device.'),
          findsOneWidget,
        );
      } else {
        expect(
          find.textContaining(
            status == 'denied'
                ? 'Allow Music and audio'
                : 'Local music could not be loaded',
          ),
          findsOneWidget,
        );
        query.allowed = true;
        query.fail = false;
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();
        expect(find.text('Song 2'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in MelodifyThemeId.values) {
    testWidgets('Home displays real data in ${theme.label} on a small screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = LocalMusicLibrary(query: HomeQuery());
      final history = PlaybackHistory(store: MemoryStore());
      final controller = PlaybackController(HomePlayer(), history: history);
      addTearDown(controller.dispose);
      addTearDown(history.dispose);
      addTearDown(library.dispose);
      await mount(tester, library, history, controller, theme: theme);
      expect(find.text('Quick Access'), findsOneWidget);
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Song 2'), findsOneWidget);
      expect(find.textContaining('Play a local song'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
