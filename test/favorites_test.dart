import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/library/favorites.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_queue.dart';
import 'package:melodify/screens/liked_songs_screen.dart';
import 'package:melodify/screens/now_playing_screen.dart';
import 'package:melodify/screens/search_screen.dart';
import 'package:melodify/screens/local_music_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:melodify/widgets/favorite_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_v1_test.dart' show song, HomeQuery, HomePlayer;

class Store implements FavoritesStore {
  List<String> data = [];
  bool fail = false;
  Completer<List<String>>? pending;
  @override
  Future<List<String>> read() async {
    if (fail) throw StateError('unavailable');
    return pending == null ? List.of(data) : pending!.future;
  }

  @override
  Future<void> write(List<String> keys) async {
    await Future<void>.value();
    if (fail) throw StateError('unavailable');
    data = List.of(keys);
  }
}

class Player extends HomePlayer {
  int loads = 0;
  Duration positionValue = const Duration(seconds: 42);
  @override
  Duration get position => positionValue;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  Stream<Duration> get positionStream => Stream.value(position);
  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) {
    loads++;
    return super.setFilePath(path);
  }
}

void main() {
  test(
    'like, duplicate prevention, newest order, unlike and re-like',
    () async {
      final f = Favorites(store: Store());
      addTearDown(f.dispose);
      await f.like(song(1));
      await f.like(song(2));
      await f.like(song(1));
      expect(f.resolve([song(1), song(2)]).map((s) => s.id), [2, 1]);
      await f.unlike(song(1));
      expect(f.isLiked(song(1)), isFalse);
      await f.like(song(1));
      expect(f.resolve([song(1), song(2)]).map((s) => s.id), [1, 2]);
    },
  );

  test('preferences persist order and unlikes across new instances', () async {
    SharedPreferences.setMockInitialValues({});
    final first = Favorites();
    final restored = Favorites();
    addTearDown(first.dispose);
    addTearDown(restored.dispose);
    await first.like(song(1));
    await first.like(song(2));
    await first.like(song(3));
    await first.unlike(song(2));
    await restored.restore();
    expect(restored.keys, ['path:/Music/3.mp3', 'path:/Music/1.mp3']);
    expect(
      (await SharedPreferences.getInstance()).getStringList(
        PreferencesFavoritesStore.preferenceKey,
      ),
      restored.keys,
    );
  });

  test('restore deduplicates and missing songs remain stored', () async {
    final store = Store()
      ..data = [
        '',
        'path:/Music/2.mp3',
        'path:/Music/2.mp3',
        'path:/Music/1.mp3',
      ];
    final f = Favorites(store: store);
    addTearDown(f.dispose);
    await f.restore();
    expect(f.resolve([song(1)]).map((s) => s.id), [1]);
    expect(f.keys, ['path:/Music/2.mp3', 'path:/Music/1.mp3']);
    expect(f.resolve([song(1), song(2)]).map((s) => s.id), [2, 1]);
  });

  test(
    'toggles during restore and serialized writes preserve final state',
    () async {
      final store = Store()..pending = Completer<List<String>>();
      final f = Favorites(store: store);
      addTearDown(f.dispose);
      final a = f.toggle(song(1));
      final b = f.toggle(song(1));
      final c = f.like(song(2));
      store.pending!.complete(['path:/Music/1.mp3']);
      await Future.wait([a, b, c]);
      expect(f.keys, ['path:/Music/2.mp3', 'path:/Music/1.mp3']);
      expect(store.data, f.keys);
    },
  );

  test(
    'save failures retain session likes and recover on later changes',
    () async {
      final store = Store();
      final f = Favorites(store: store);
      addTearDown(f.dispose);
      await f.restore();
      store.fail = true;
      await f.like(song(1));
      expect(f.isLiked(song(1)), isTrue);
      expect(f.storageAvailable, isFalse);
      store.fail = false;
      await f.like(song(2));
      expect(f.storageAvailable, isTrue);
      expect(store.data, f.keys);
    },
  );

  testWidgets(
    'Liked Songs queue follows displayed order/index and survives unlikes',
    (tester) async {
      final f = Favorites(store: Store());
      final library = LocalMusicLibrary(query: HomeQuery());
      final player = Player()..positionValue = Duration.zero;
      final controller = PlaybackController(player);
      addTearDown(f.dispose);
      addTearDown(library.dispose);
      addTearDown(controller.dispose);
      await f.like(song(1));
      await f.like(song(99));
      await f.like(song(2));
      await tester.pumpWidget(
        MaterialApp(
          theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
          home: LikedSongsScreen(
            favorites: f,
            library: library,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Song 99'), findsNothing);
      await tester.tap(find.text('Song 1'));
      await tester.pumpAndSettle();
      expect(controller.queue.items.map((s) => s.id), [2, 1]);
      expect(controller.currentIndex, 1);
      await controller.previous();
      expect(controller.currentSong!.id, 2);
      await controller.next();
      expect(controller.currentSong!.id, 1);
      await tester.tap(find.byTooltip('Unlike Song 1'));
      await tester.pumpAndSettle();
      expect(find.text('Song 1'), findsNothing);
      expect(controller.queue.items.map((s) => s.id), [2, 1]);
      expect(controller.currentIndex, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Now Playing and Search hearts synchronize without touching playback',
    (tester) async {
      final f = Favorites(store: Store());
      final library = LocalMusicLibrary(query: HomeQuery());
      final player = Player();
      final controller = PlaybackController(player);
      addTearDown(f.dispose);
      addTearDown(library.dispose);
      addTearDown(controller.dispose);
      await f.restore();
      await library.load();
      await controller.selectSong(library.songs, library.songs.first);
      controller.toggleShuffle();
      await tester.pumpWidget(
        MaterialApp(
          theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
          home: NowPlayingScreen(controller: controller, favorites: f),
        ),
      );
      await tester.tap(find.byTooltip('Like Song 1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlike Song 1'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
          home: Scaffold(
            body: SearchScreen(
              controller: controller,
              library: library,
              favorites: f,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Song 1');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unlike Song 1'));
      await tester.pumpAndSettle();
      expect(f.isLiked(song(1)), isFalse);
      await tester.pumpWidget(
        MaterialApp(
          theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
          home: NowPlayingScreen(controller: controller, favorites: f),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Like Song 1'), findsOneWidget);
      expect(player.loads, 1);
      expect(player.position, const Duration(seconds: 42));
      expect(player.playing, isTrue);
      expect(controller.mode, PlaybackMode.shuffle);
      expect(controller.queue.items.map((s) => s.id), [1, 2]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Local Music heart does not select a song', (tester) async {
    final f = Favorites(store: Store());
    final library = LocalMusicLibrary(query: HomeQuery());
    final controller = PlaybackController(Player());
    addTearDown(f.dispose);
    addTearDown(library.dispose);
    addTearDown(controller.dispose);
    await f.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
        home: LocalMusicScreen(
          controller: controller,
          library: library,
          favorites: f,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Like Song 1'));
    await tester.pumpAndSettle();
    expect(f.isLiked(song(1)), isTrue);
    expect(controller.currentSong, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty and unavailable states', (tester) async {
    final f = Favorites(store: Store());
    final library = LocalMusicLibrary(query: HomeQuery());
    final controller = PlaybackController(Player());
    addTearDown(f.dispose);
    addTearDown(library.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
        home: LikedSongsScreen(
          favorites: f,
          library: library,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No liked songs yet'), findsOneWidget);
    await tester.runAsync(() => f.like(song(99)));
    await tester.pumpAndSettle();
    expect(find.text('Your liked songs are unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('filled hearts use all six theme accents', (tester) async {
    final f = Favorites(store: Store());
    addTearDown(f.dispose);
    await f.like(song(1));
    for (final id in MelodifyThemeId.values) {
      final theme = MelodifyTheme.forId(id);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: FavoriteButton(favorites: f, song: song(1)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.color, theme.extension<MelodifyPalette>()!.primary);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    }
  });
}
