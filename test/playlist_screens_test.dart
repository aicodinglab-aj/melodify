import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/library/favorites.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/playlists.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_queue.dart';
import 'package:melodify/screens/playlists_screen.dart';
import 'package:melodify/screens/playlist_details_screen.dart';
import 'package:melodify/screens/playlist_add_songs_screen.dart';
import 'package:melodify/screens/local_music_screen.dart';
import 'package:melodify/screens/search_screen.dart';
import 'package:melodify/screens/liked_songs_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:melodify/widgets/favorite_button.dart';

import 'home_v1_test.dart' show HomeQuery, song;
import 'favorites_test.dart' show Store, Player;
import 'playlists_test.dart' show MemoryPlaylistsStore;

void main() {
  late Playlists playlists;
  late Favorites favorites;
  late LocalMusicLibrary library;
  late HomeQuery query;
  late Player player;
  late PlaybackController controller;
  Future<void> setup() async {
    playlists = Playlists(store: MemoryPlaylistsStore());
    favorites = Favorites(store: Store());
    query = HomeQuery();
    library = LocalMusicLibrary(query: query);
    player = Player()..positionValue = Duration.zero;
    controller = PlaybackController(player);
    await playlists.restore();
    await favorites.restore();
    await library.load();
  }

  tearDown(() {
    playlists.dispose();
    favorites.dispose();
    library.dispose();
    controller.dispose();
  });

  Widget details(String id) => PlaylistDetailsScreen(
    playlistId: id,
    playlists: playlists,
    library: library,
    controller: controller,
    favorites: favorites,
  );
  Widget listing() => PlaylistsScreen(
    playlists: playlists,
    library: library,
    controller: controller,
    favorites: favorites,
  );
  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.forId(MelodifyThemeId.melodifyGreen),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String title, String label) async {
    await tester.tap(find.byTooltip('Actions for $title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('create dialog validates names and shows a new playlist', (
    tester,
  ) async {
    await setup();
    await mount(tester, listing());
    expect(find.text('No playlists yet'), findsOneWidget);
    await tester.tap(find.text('Create Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a playlist name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Road Trip  ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('0 available songs'), findsOneWidget);
    await tester.tap(find.text('Create Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ROAD TRIP');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(
      find.text('A playlist with this name already exists.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'details queue uses available order and selected index, Play and Shuffle',
    (tester) async {
      await setup();
      final p = await playlists.create('Mix');
      await playlists.addSongs(p.id, [song(99), song(2), song(1)]);
      await mount(tester, details(p.id));
      expect(find.text('Song 99'), findsNothing);
      await tester.tap(find.text('Song 1'));
      await tester.pumpAndSettle();
      expect(controller.queue.items.map((s) => s.id), [2, 1]);
      expect(controller.currentIndex, 1);
      await controller.previous();
      expect(controller.currentSong!.id, 2);
      await controller.next();
      expect(controller.currentSong!.id, 1);
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect(controller.mode, PlaybackMode.shuffle);
      final index = controller.currentIndex;
      await controller.next();
      expect(controller.currentIndex, isNot(index));
      await controller.previous();
      expect(controller.currentIndex, index);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(controller.currentSong!.id, 2);
      expect(controller.mode, PlaybackMode.sequential);
      controller.cycleRepeat();
      expect(controller.mode, PlaybackMode.repeatAll);
      await controller.previous();
      expect(controller.currentSong!.id, 1);
      controller.cycleRepeat();
      expect(controller.mode, PlaybackMode.repeatOne);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'remove keeps favorites, other playlists, library and active queue',
    (tester) async {
      await setup();
      final a = await playlists.create('A');
      final b = await playlists.create('B');
      await playlists.addSongs(a.id, [song(1), song(2)]);
      await playlists.addSongs(b.id, [song(1)]);
      await favorites.like(song(1));
      await mount(tester, details(a.id));
      await tester.tap(find.text('Song 1'));
      await tester.pumpAndSettle();
      final loads = player.loads;
      await action(tester, 'Song 1', 'Remove from playlist');
      expect(playlists.byId(a.id)!.songKeys, ['path:/Music/2.mp3']);
      expect(playlists.byId(b.id)!.songKeys, ['path:/Music/1.mp3']);
      expect(favorites.isLiked(song(1)), isTrue);
      expect(library.songs.length, 2);
      expect(controller.queue.items.map((s) => s.id), [1, 2]);
      expect(player.loads, loads);
      expect(player.playing, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rename and confirmed deletion return to playlist list, cancel preserves data',
    (tester) async {
      await setup();
      final p = await playlists.create('Before');
      await playlists.addSongs(p.id, [song(1)]);
      await favorites.like(song(1));
      await controller.selectSong(library.songs, library.songs.first);
      await mount(tester, listing());
      await tester.tap(find.text('Before'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'After');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('After'), findsOneWidget);
      expect(playlists.byId(p.id)!.songKeys.length, 1);
      Future<void> openDelete() async {
        await tester.tap(find.byTooltip('Playlist options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete playlist'));
        await tester.pumpAndSettle();
      }

      await openDelete();
      expect(
        find.text(
          'This will remove the playlist, but your music files will not be deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(playlists.byId(p.id), isNotNull);
      await openDelete();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      expect(playlists.items, isEmpty);
      expect(favorites.isLiked(song(1)), isTrue);
      expect(controller.queue.items.length, 2);
      expect(player.playing, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Add Songs preserves selections across search and appends in selection order',
    (tester) async {
      await setup();
      final p = await playlists.create('Mix');
      await mount(tester, details(p.id));
      await tester.tap(find.text('Add Songs'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistAddSongsScreen), findsOneWidget);
      await tester.tap(find.text('Song 2'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Song 1');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Song 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 2 songs'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistDetailsScreen), findsOneWidget);
      expect(playlists.resolve(p.id, library.songs).map((s) => s.id), [2, 1]);
      expect(query.calls, 1);
      expect(player.loads, 0);
      await tester.tap(find.text('Add Songs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Already in playlist'), findsNWidgets(2));
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final origin in ['Local Music', 'Search', 'Liked Songs']) {
    testWidgets(
      '$origin Add to playlist creates first playlist and returns without playback',
      (tester) async {
        await setup();
        await favorites.like(song(1));
        final screen = switch (origin) {
          'Search' => Scaffold(
            body: SearchScreen(
              controller: controller,
              library: library,
              favorites: favorites,
              playlists: playlists,
            ),
          ),
          'Liked Songs' => LikedSongsScreen(
            controller: controller,
            library: library,
            favorites: favorites,
            playlists: playlists,
          ),
          _ => LocalMusicScreen(
            controller: controller,
            library: library,
            favorites: favorites,
            playlists: playlists,
          ),
        };
        await mount(tester, screen);
        if (origin == 'Search') {
          await tester.enterText(find.byType(TextField), 'Song 1');
          await tester.pumpAndSettle();
        }
        await action(tester, 'Song 1', 'Add to playlist');
        expect(
          find.text('No playlists yet. Create one to add this song.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Create Playlist'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(TextField),
          ),
          'New mix',
        );
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        expect(playlists.items.single.songKeys, ['path:/Music/1.mp3']);
        expect(find.byType(AlertDialog), findsNothing);
        expect(controller.currentSong, isNull);
        expect(player.loads, 0);
        await action(tester, 'Song 1', 'Add to playlist');
        await tester.tap(find.text('New mix'));
        await tester.pumpAndSettle();
        expect(playlists.items.single.songKeys.length, 1);
        expect(find.text('Song is already in this playlist.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('playlist heart and another shared favorite view synchronize', (
    tester,
  ) async {
    await setup();
    final p = await playlists.create('Mix');
    await playlists.addSongs(p.id, [song(1)]);
    await mount(tester, details(p.id));
    await tester.tap(find.byTooltip('Like Song 1'));
    await tester.pumpAndSettle();
    expect(favorites.isLiked(song(1)), isTrue);
    expect(player.loads, 0);
    await favorites.unlike(song(1));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Like Song 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Like Song 1'));
    await tester.pumpAndSettle();
    await mount(
      tester,
      Scaffold(
        body: FavoriteButton(favorites: favorites, song: song(1)),
      ),
    );
    expect(find.byTooltip('Unlike Song 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'missing-only playlist disables playback and handles denied discovery retry',
    (tester) async {
      await setup();
      final p = await playlists.create('Missing');
      await playlists.addSongs(p.id, [song(99)]);
      await mount(tester, details(p.id));
      expect(
        find.text(
          'Songs in this playlist are currently unavailable. Their saved entries are kept.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Play'))
            .onPressed,
        isNull,
      );
      query.allowed = false;
      await library.load(retry: true);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Allow Music and audio access'),
        findsOneWidget,
      );
      query.allowed = true;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('0 available songs'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('playlist screens render in all themes at phone width', (
    tester,
  ) async {
    await setup();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = await playlists.create('A long playlist name for a small screen');
    await playlists.addSongs(p.id, [song(1), song(2)]);
    await favorites.like(song(1));
    for (final id in MelodifyThemeId.values) {
      await tester.pumpWidget(
        MaterialApp(theme: MelodifyTheme.forId(id), home: details(p.id)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Unlike Song 1'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
