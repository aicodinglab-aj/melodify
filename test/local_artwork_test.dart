import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:melodify/main.dart';
import 'package:melodify/library/local_artwork_repository.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/favorites.dart';
import 'package:melodify/library/playlists.dart';
import 'package:melodify/models/local_music_folder.dart';
import 'package:melodify/screens/local_music_screen.dart';
import 'package:melodify/screens/home_screen.dart';
import 'package:melodify/screens/playlists_screen.dart';
import 'package:melodify/screens/playlist_add_songs_screen.dart';
import 'package:melodify/screens/local_music_folder_screen.dart';
import 'package:melodify/screens/search_screen.dart';
import 'package:melodify/screens/liked_songs_screen.dart';
import 'package:melodify/screens/playlist_details_screen.dart';
import 'package:melodify/screens/now_playing_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:melodify/widgets/local_song_artwork.dart';
import 'package:melodify/widgets/music_artwork.dart';

import 'background_playback_test.dart' show BackgroundRig;
import 'home_v1_test.dart' show song, HomeQuery;
import 'favorites_test.dart' show Store;
import 'playlists_test.dart' show MemoryPlaylistsStore;
import 'mini_player_test.dart' as mini;

class ArtworkQuery extends Fake implements OnAudioQuery {
  final calls = <(int, int?)>[];
  final data = <int, Uint8List?>{};
  final gates = <int, Completer<Uint8List?>>{};
  bool fail = false;
  @override
  Future<Uint8List?> queryArtwork(
    int id,
    ArtworkType type, {
    ArtworkFormat? format,
    int? size,
    int? quality,
  }) async {
    calls.add((id, size));
    expect(type, ArtworkType.AUDIO);
    if (fail) throw StateError('unavailable');
    return gates[id] == null ? data[id] : await gates[id]!.future;
  }
}

Widget artworkApp({required Widget home, ThemeData? theme}) => MaterialApp(
  theme: theme ?? MelodifyTheme.dark,
  home: MediaQuery(
    data: const MediaQueryData(devicePixelRatio: 1),
    child: Scaffold(body: home),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 2);
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  test(
    'coalesces requests and retains positive and negative results',
    () async {
      final q = ArtworkQuery()..data[1] = png;
      final r = LocalArtworkRepository(query: q);
      final a = r.load(song(1));
      expect(identical(a, r.load(song(1))), isTrue);
      expect(await a, png);
      await r.load(song(1));
      await r.load(song(2));
      await r.load(song(2));
      expect(q.calls.length, 2);
    },
  );
  test('size buckets and LRU entry/byte bounds', () async {
    final q = ArtworkQuery()..data.addAll({1: png, 2: png});
    final r = LocalArtworkRepository(
      query: q,
      maxEntries: 2,
      maxBytes: png.length * 2,
    );
    for (final pixels in [40, 200, 900]) {
      await r.load(song(1), pixels: pixels);
    }
    expect(q.calls.map((c) => c.$2), [128, 256, 512]);
    expect(r.cachedEntries, 2);
    expect(r.cachedBytes, png.length * 2);
    await r.load(song(1), pixels: 40);
    expect(q.calls.length, 4);
    final tiny = LocalArtworkRepository(query: q, maxBytes: 1);
    await tiny.load(song(1));
    expect(tiny.cachedBytes, 0);
  });
  test('bounds active requests to two and pending requests to 128', () async {
    final q = ArtworkQuery();
    q.gates[0] = Completer();
    q.gates[1] = Completer();
    final r = LocalArtworkRepository(query: q);
    final work = List.generate(129, (i) => r.load(song(i)));
    expect(q.calls.length, 2);
    expect(await work.last, isNull);
    q.gates[0]!.complete(null);
    q.gates[1]!.complete(null);
    await Future.wait(work);
    expect(q.calls.length, 128);
  });
  for (final kind in ['missing', 'failure', 'corrupt', 'oversized']) {
    testWidgets('$kind artwork uses stable fallback without retries', (
      tester,
    ) async {
      final q = ArtworkQuery()..fail = kind == 'failure';
      q.data[1] = kind == 'corrupt'
          ? Uint8List.fromList([1, 2, 3])
          : kind == 'oversized'
          ? Uint8List(600 * 1024)
          : null;
      final r = LocalArtworkRepository(query: q);
      Future<void> show() => tester.pumpWidget(
        LocalArtworkScope(
          repository: r,
          child: artworkApp(
            home: Scaffold(body: LocalSongArtwork(song: song(1))),
          ),
        ),
      );
      await show();
      await tester.runAsync(() => r.load(song(1)));
      await tester.pumpAndSettle();
      expect(find.byType(MusicArtwork), findsOneWidget);
      await show();
      await tester.pumpAndSettle();
      expect(q.calls.length, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('real artwork is unchanged across every theme', (tester) async {
    final q = ArtworkQuery()..data[1] = png;
    final r = LocalArtworkRepository(query: q);
    await tester.runAsync(() => r.load(song(1)));
    for (final theme in MelodifyThemeId.values) {
      await tester.pumpWidget(
        LocalArtworkScope(
          repository: r,
          child: artworkApp(
            theme: MelodifyTheme.forId(theme),
            home: Scaffold(body: LocalSongArtwork(song: song(1))),
          ),
        ),
      );
      await tester.runAsync(() => r.load(song(1)));
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        ((image.image as ResizeImage).imageProvider as MemoryImage).bytes,
        png,
      );
      expect(image.color, isNull);
    }
    expect(q.calls.length, 1);
  });
  testWidgets('late old artwork cannot appear on a new song', (tester) async {
    final q = ArtworkQuery()..gates[1] = Completer();
    final r = LocalArtworkRepository(query: q);
    Future<void> show(int id) => tester.pumpWidget(
      LocalArtworkScope(
        repository: r,
        child: artworkApp(home: LocalSongArtwork(song: song(id))),
      ),
    );
    await show(1);
    await show(2);
    await tester.runAsync(() async {
      q.gates[1]!.complete(png);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(MusicArtwork), findsOneWidget);
  });
  for (final hasCover in [true, false]) {
    testWidgets('playlist selects first real cover or fallback: $hasCover', (
      tester,
    ) async {
      final q = ArtworkQuery();
      if (hasCover) q.data[2] = png;
      final r = LocalArtworkRepository(query: q);
      if (hasCover) await tester.runAsync(() => r.load(song(2)));
      await tester.pumpWidget(
        LocalArtworkScope(
          repository: r,
          child: artworkApp(
            home: LocalSongArtwork(songs: [song(1), song(2), song(3)]),
          ),
        ),
      );
      await tester.runAsync(() async {
        await r.load(song(1));
        await r.load(song(2));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), hasCover ? findsOneWidget : findsNothing);
      expect(q.calls.map((c) => c.$1), hasCover ? [2, 1] : [1, 2, 3]);
    });
  }
  testWidgets('large lazy list only queries visible children', (tester) async {
    final q = ArtworkQuery();
    final r = LocalArtworkRepository(query: q);
    await tester.pumpWidget(
      LocalArtworkScope(
        repository: r,
        child: artworkApp(
          home: ListView.builder(
            itemCount: 1000,
            itemExtent: 64,
            itemBuilder: (_, i) => LocalSongArtwork(song: song(i)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(q.calls.length, greaterThan(0));
    expect(q.calls.length, lessThan(30));
  });
  for (final screen in [
    'Local Music',
    'Folder',
    'Search',
    'Liked',
    'Playlist',
    'Home',
    'Covers',
    'Add Songs',
  ]) {
    testWidgets('$screen rows associate artwork with the right song', (
      tester,
    ) async {
      final rig = (await tester.runAsync(() async => BackgroundRig()))!;
      final libraryQuery = HomeQuery();
      final library = LocalMusicLibrary(query: libraryQuery);
      final favorites = (await tester.runAsync(
        () async => Favorites(store: Store()),
      ))!;
      final playlists = (await tester.runAsync(
        () async => Playlists(store: MemoryPlaylistsStore()),
      ))!;
      late String playlistId;
      await tester.runAsync(() async {
        await library.load();
        await favorites.like(song(1));
        playlistId = (await playlists.create('Mix')).id;
        await playlists.addSongs(playlistId, [song(1)]);
      });
      final q = ArtworkQuery()..data[1] = png;
      final r = LocalArtworkRepository(query: q);
      await tester.runAsync(() => r.load(song(1)));
      final Widget page = switch (screen) {
        'Home' => HomeScreen(
          controller: rig.controller,
          library: library,
          history: rig.history,
          onOpenLocalMusic: (_) {},
        ),
        'Covers' => PlaylistsScreen(
          playlists: playlists,
          library: library,
          controller: rig.controller,
        ),
        'Add Songs' => PlaylistAddSongsScreen(
          playlists: playlists,
          playlistId: playlistId,
          library: library,
        ),
        'Local Music' => LocalMusicScreen(
          controller: rig.controller,
          library: library,
        ),
        'Folder' => LocalMusicFolderScreen(
          folder: LocalMusicFolder(path: '/Music', songs: library.songs),
          audioPlayer: rig.player,
          onPlaySong: (_) async {},
        ),
        'Search' => SearchScreen(controller: rig.controller, library: library),
        'Liked' => LikedSongsScreen(
          favorites: favorites,
          library: library,
          controller: rig.controller,
        ),
        _ => PlaylistDetailsScreen(
          playlistId: playlistId,
          playlists: playlists,
          library: library,
          controller: rig.controller,
        ),
      };
      await tester.pumpWidget(
        LocalArtworkScope(
          repository: r,
          child: artworkApp(home: page),
        ),
      );
      await tester.pumpAndSettle();
      if (screen == 'Search') {
        await tester.enterText(find.byType(TextField), 'Song 1');
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() => r.load(song(1)));
      await tester.pumpAndSettle();
      final art = find.byWidgetPredicate(
        (w) =>
            w is LocalSongArtwork &&
            (w.song?.id == 1 || w.songs?.firstOrNull?.id == 1),
      );
      expect(art, findsOneWidget);
      expect(
        find.descendant(of: art, matching: find.byType(Image)),
        findsOneWidget,
      );
      if (screen == 'Search') {
        final count = q.calls.length;
        await tester.enterText(find.byType(TextField), 'Song');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Song 1');
        await tester.pumpAndSettle();
        expect(q.calls.where((c) => c.$1 == 1).length, 1);
        expect(q.calls.length, greaterThanOrEqualTo(count));
      }
      expect(libraryQuery.calls, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(rig.dispose);
      library.dispose();
      favorites.dispose();
      playlists.dispose();
    });
  }
  testWidgets('mini-player and Now Playing follow current track artwork', (
    tester,
  ) async {
    final runtime = await mini.mount(tester);
    final q = ArtworkQuery()..data.addAll({1: png, 2: png});
    final r = LocalArtworkRepository(query: q);
    await tester.runAsync(() async {
      for (final id in [1, 2]) {
        for (final pixels in [128, 256, 512]) {
          await r.load(song(id), pixels: pixels);
        }
      }
    });
    // Retain the mounted app while supplying the same shared repository.
    final app = MelodifyApp(runtime: runtime);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LocalArtworkScope(repository: r, child: app));
    await tester.runAsync(
      () => runtime.controller.selectSong([song(1), song(2)], song(1)),
    );
    await tester.pumpAndSettle();
    final current = find.descendant(
      of: mini.mini,
      matching: find.byType(LocalSongArtwork),
    );
    expect(tester.widget<LocalSongArtwork>(current).song!.id, 1);
    await tester.runAsync(() => r.load(song(1)));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: current, matching: find.byType(Image)),
      findsOneWidget,
    );
    // A standalone Now Playing observes the same production controller.
    await tester.pumpWidget(
      LocalArtworkScope(
        repository: r,
        child: artworkApp(
          home: NowPlayingScreen(controller: runtime.controller),
        ),
      ),
    );
    await tester.runAsync(() => r.load(song(1), pixels: 256));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LocalSongArtwork>(find.byType(LocalSongArtwork)).song!.id,
      1,
    );
    await tester.runAsync(runtime.controller.next);
    await tester.pumpAndSettle();
    expect(
      tester.widget<LocalSongArtwork>(find.byType(LocalSongArtwork)).song!.id,
      2,
    );
    expect(find.byType(Image), findsOneWidget);
    await mini.finish(tester, runtime);
  });
}
