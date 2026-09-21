import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/screens/search_screen.dart';
import 'package:melodify/screens/local_music_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:melodify/widgets/local_song_list.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

final songs = [
  SongModel({
    '_id': 1,
    '_data': '/Music/a.mp3',
    'title': 'Amber Sky',
    'artist': 'River Band',
    'album': 'Evening',
  }),
  SongModel({
    '_id': 2,
    '_data': '/Music/b.mp3',
    'title': 'Blue Sky',
    'artist': 'Other Artist',
    'album': 'Morning',
  }),
  SongModel({
    '_id': 3,
    '_data': '/Music/c.mp3',
    'title': 'Clouds',
    'artist': null,
    'album': '<unknown>',
  }),
];

class Query extends Fake implements OnAudioQuery {
  bool allowed = true;
  bool fail = false;
  int calls = 0;
  List<SongModel> collection = songs;
  Completer<List<SongModel>>? pending;
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
    return pending == null ? collection : await pending!.future;
  }
}

class Player extends Fake implements AudioPlayer {
  String? loaded;
  int plays = 0;
  @override
  PlayerState get playerState => PlayerState(false, ProcessingState.ready);
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  AudioSource? get audioSource => null;
  @override
  Duration get position => Duration.zero;
  @override
  Future<void> stop() async {}
  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loaded = filePath;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  for (final entry in {
    'title': 'Amber',
    'artist': 'River',
    'album': 'Evening',
    'case insensitive': 'aMbEr',
    'trim whitespace': '  Amber  ',
  }.entries) {
    test('search by ${entry.key}', () {
      expect(searchLocalSongs(songs, entry.value).map((s) => s.id), [1]);
    });
  }
  test('empty query and unknown metadata do not produce results', () {
    expect(searchLocalSongs(songs, ''), isEmpty);
    expect(searchLocalSongs(songs, '   '), isEmpty);
    expect(searchLocalSongs(songs, '<unknown>'), isEmpty);
    expect(searchLocalSongs(songs, 'missing'), isEmpty);
    expect(searchLocalSongs(songs, 'Clouds').single.id, 3);
  });

  SongModel rankedSong(int id, String title, {String? artist, String? album}) =>
      SongModel({
        '_id': id,
        '_data': '/Music/$id.mp3',
        'title': title,
        'artist': artist,
        'album': album,
      });

  final rankedSongs = [
    rankedSong(9, 'A album contains', album: 'Cinema'),
    rankedSong(8, 'B album prefix', album: 'Magic'),
    rankedSong(7, 'C album exact', album: 'Ma'),
    rankedSong(6, 'D artist contains', artist: 'Cinema', album: 'Ma'),
    rankedSong(5, 'E artist prefix', artist: 'Magic'),
    rankedSong(4, 'F artist exact', artist: 'Ma'),
    rankedSong(3, 'Cinema', artist: 'Ma'),
    rankedSong(2, 'Magic'),
    rankedSong(1, 'Ma'),
  ];

  test('all nine relevance levels use the strongest matching field', () {
    expect(searchLocalSongs(rankedSongs, 'ma').map((s) => s.id), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
    ]);
    expect(rankedSongs.map((s) => s.id), [9, 8, 7, 6, 5, 4, 3, 2, 1]);
  });

  test('ranking is case insensitive and trims the query', () {
    expect(searchLocalSongs(rankedSongs, '  mA  ').map((s) => s.id), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
    ]);
  });

  test('equal ranks sort by case-insensitive title then deterministic ID', () {
    final input = [
      rankedSong(5, 'zebra', artist: 'ma'),
      rankedSong(3, 'beta', artist: 'MA'),
      rankedSong(2, 'Alpha', artist: 'Ma'),
      rankedSong(1, 'alpha', artist: 'ma'),
    ];
    expect(searchLocalSongs(input, 'ma').map((s) => s.id), [1, 2, 3, 5]);
    expect(searchLocalSongs(input.reversed.toList(), 'ma').map((s) => s.id), [
      1,
      2,
      3,
      5,
    ]);
  });

  test('library shares pending load and caches discovery', () async {
    final query = Query()..pending = Completer<List<SongModel>>();
    final library = LocalMusicLibrary(query: query);
    addTearDown(library.dispose);
    final first = library.load();
    final second = library.load();
    query.pending!.complete(songs);
    await Future.wait([first, second]);
    await library.load();
    expect(query.calls, 1);
    expect(() => library.songs.clear(), throwsUnsupportedError);
  });

  Future<void> mount(
    WidgetTester tester,
    LocalMusicLibrary library,
    PlaybackController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.dark,
        home: Scaffold(
          body: SearchScreen(library: library, controller: controller),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'live search states and selected result queue survive query changes',
    (tester) async {
      final query = Query();
      final library = LocalMusicLibrary(query: query);
      final player = Player();
      final controller = PlaybackController(player);
      addTearDown(library.dispose);
      addTearDown(controller.dispose);
      await library.load();
      await mount(tester, library, controller);
      expect(
        find.text('Search your local music by song title, artist, or album.'),
        findsOneWidget,
      );
      expect(find.text('Amber Sky'), findsNothing);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump();
      expect(find.text('No songs found'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' sky ');
      await tester.pump();
      expect(find.text('Amber Sky'), findsOneWidget);
      expect(find.textContaining('Evening'), findsOneWidget);
      await tester.tap(find.text('Blue Sky'));
      await tester.pumpAndSettle();
      expect(controller.queue.items.map((s) => s.id), [1, 2]);
      expect(controller.currentIndex, 1);
      expect(player.loaded, '/Music/b.mp3');
      expect(player.plays, 1);
      await tester.enterText(find.byType(TextField), 'Clouds');
      await tester.pump();
      expect(controller.currentIndex, 1);
      expect(controller.queue.items.map((s) => s.id), [1, 2]);
      expect(player.plays, 1);
      await controller.previous();
      expect(controller.currentSong!.id, 1);
      await controller.next();
      expect(controller.currentSong!.id, 2);
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      expect(
        find.text('Search your local music by song title, artist, or album.'),
        findsOneWidget,
      );
      expect(query.calls, 1);
    },
  );

  testWidgets(
    'ranked display order becomes queue order at selected index three',
    (tester) async {
      final query = Query()..collection = rankedSongs;
      final library = LocalMusicLibrary(query: query);
      final player = Player();
      final controller = PlaybackController(player);
      addTearDown(library.dispose);
      addTearDown(controller.dispose);
      await library.load();
      await mount(tester, library, controller);
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump();
      final displayed = tester
          .widget<LocalSongList>(find.byType(LocalSongList))
          .songs;
      expect(displayed.map((s) => s.id), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(
        tester.getTopLeft(find.text('Ma').first).dy,
        lessThan(tester.getTopLeft(find.text('Magic').first).dy),
      );
      await tester.ensureVisible(find.text('F artist exact'));
      await tester.tap(find.text('F artist exact'));
      await tester.pumpAndSettle();
      expect(controller.queue.items, orderedEquals(displayed));
      expect(controller.currentIndex, 3);
      expect(player.loaded, '/Music/4.mp3');
      expect(player.plays, 1);
      await controller.next();
      expect(controller.currentSong!.id, 5);
      await controller.previous();
      expect(controller.currentSong!.id, 4);
      await tester.enterText(find.byType(TextField), 'Cinema');
      await tester.pump();
      expect(controller.queue.items, orderedEquals(displayed));
      expect(query.calls, 1);
    },
  );

  testWidgets('Local Music loads the same collection observed by Search', (
    tester,
  ) async {
    final query = Query();
    final library = LocalMusicLibrary(query: query);
    final controller = PlaybackController(Player());
    addTearDown(library.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.dark,
        home: Scaffold(
          body: IndexedStack(
            index: 1,
            children: [
              SearchScreen(library: library, controller: controller),
              LocalMusicScreen(library: library, controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Amber Sky'), findsOneWidget);
    expect(library.songs.map((s) => s.id), [1, 2, 3]);
    await library.load();
    expect(query.calls, 1);
  });

  for (final state in ['loading', 'denied', 'failed', 'empty']) {
    testWidgets('search handles $state library', (tester) async {
      final query = Query();
      if (state == 'loading') query.pending = Completer<List<SongModel>>();
      if (state == 'denied') query.allowed = false;
      if (state == 'failed') query.fail = true;
      if (state == 'empty') query.collection = [];
      final library = LocalMusicLibrary(query: query);
      final controller = PlaybackController(Player());
      addTearDown(library.dispose);
      addTearDown(controller.dispose);
      final loading = library.load();
      if (state != 'loading') await loading;
      await mount(tester, library, controller);
      if (state == 'loading') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        query.pending!.complete(songs);
        await loading;
      } else if (state == 'empty') {
        expect(
          find.text('No local songs were found on this device.'),
          findsOneWidget,
        );
      } else {
        expect(
          find.textContaining(
            state == 'denied'
                ? 'Allow Music and audio'
                : 'Local music could not be loaded',
          ),
          findsOneWidget,
        );
        query.allowed = true;
        query.fail = false;
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();
        expect(
          find.text('Search your local music by song title, artist, or album.'),
          findsOneWidget,
        );
      }
    });
  }
}
