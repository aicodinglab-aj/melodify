import 'package:just_audio/just_audio.dart';
import 'package:melodify/library/playback_history.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_runtime.dart';
import 'package:melodify/screens/playlists_screen.dart';
import 'package:melodify/screens/playlist_details_screen.dart';
import 'package:melodify/screens/liked_songs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/main.dart';
import 'package:melodify/screens/home_screen.dart';
import 'package:melodify/screens/local_music_screen.dart';
import 'package:melodify/screens/local_music_folder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (_) async => <String, dynamic>{},
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.lucasjosino.on_audio_query'),
      (call) async {
        if (call.method == 'permissionsStatus' ||
            call.method == 'permissionsRequest') {
          return true;
        }
        if (call.method == 'querySongs') {
          return [
            {
              '_id': 1,
              '_data': '/Music/song.mp3',
              'title': 'Local song',
              'artist': 'Artist',
              'date_added': 100,
            },
          ];
        }
        return null;
      },
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.lucasjosino.on_audio_query'),
      null,
    );
  });

  late PlaybackRuntime runtime;
  Widget app() {
    final history = PlaybackHistory();
    runtime = PlaybackRuntime(
      controller: PlaybackController(
        AudioPlayer(handleInterruptions: false),
        history: history,
      ),
      history: history,
      library: LocalMusicLibrary(),
    );
    return MelodifyApp(runtime: runtime);
  }

  Future<void> back(WidgetTester tester, bool system) async {
    if (system) {
      await tester.binding.handlePopRoute();
    } else {
      await tester.tap(find.byType(BackButton));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Library opens shared Liked Songs and Back retains playback', (
    tester,
  ) async {
    await tester.pumpWidget((await tester.runAsync(() async => app()))!);
    await tester.pumpAndSettle();
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    home.controller.queue.select(home.library.songs, 0);
    home.controller.toggleShuffle();
    await tester.pumpAndSettle();
    await tab(tester, 'Library');
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Local Music'));
    await tester.tap(find.widgetWithText(ListTile, 'Local Music'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Like Local song'));
    await tester.pumpAndSettle();
    await back(tester, false);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Liked Songs'));
    await tester.tap(find.widgetWithText(ListTile, 'Liked Songs'));
    await tester.pumpAndSettle();
    final liked = tester.widget<LikedSongsScreen>(
      find.byType(LikedSongsScreen),
    );
    expect(identical(liked.controller, home.controller), isTrue);
    expect(identical(liked.library, home.library), isTrue);
    expect(find.byTooltip('Unlike Local song'), findsOneWidget);
    expect(find.byTooltip('Close player'), findsOneWidget);
    await back(tester, true);
    expect(find.text('Your Library'), findsOneWidget);
    expect(home.controller.currentIndex, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(runtime.dispose);
    await tester.pumpAndSettle();
  });

  for (final system in [false, true]) {
    final mode = system ? 'system Back' : 'AppBar Back';
    testWidgets(
      'Library playlist stack respects $mode and keeps the shared player',
      (tester) async {
        await tester.pumpWidget((await tester.runAsync(() async => app()))!);
        await tester.pumpAndSettle();
        final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
        home.controller.queue.select(home.library.songs, 0);
        home.controller.toggleShuffle();
        await tester.pumpAndSettle();
        await tab(tester, 'Library');
        await tester.ensureVisible(find.widgetWithText(ListTile, 'Playlists'));
        await tester.tap(find.widgetWithText(ListTile, 'Playlists'));
        await tester.pumpAndSettle();
        final screen = tester.widget<PlaylistsScreen>(
          find.byType(PlaylistsScreen),
        );
        expect(
          identical(screen.controller.player, home.controller.player),
          isTrue,
        );
        await tester.tap(find.text('Create Playlist'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Navigation Mix');
        await tester.tap(find.text('Create'));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text('Navigation Mix'));
        await tester.pumpAndSettle();
        final detail = tester.widget<PlaylistDetailsScreen>(
          find.byType(PlaylistDetailsScreen),
        );
        expect(identical(detail.playlists, screen.playlists), isTrue);
        expect(identical(detail.controller, home.controller), isTrue);
        await tester.tap(find.text('Add Songs'));
        await tester.pumpAndSettle();
        await back(tester, system);
        expect(find.byType(PlaylistDetailsScreen), findsOneWidget);
        await back(tester, system);
        expect(find.byType(PlaylistsScreen), findsOneWidget);
        await back(tester, system);
        expect(find.text('Your Library'), findsOneWidget);
        expect(find.byTooltip('Close player'), findsOneWidget);
        expect(home.controller.currentIndex, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(runtime.dispose);
        await tester.pumpAndSettle();
      },
    );
    for (final shortcut in ['Local Music', 'Songs', 'Folders']) {
      testWidgets('Home -> $shortcut -> $mode returns to Home', (tester) async {
        await tester.pumpWidget((await tester.runAsync(() async => app()))!);
        await tester.pumpAndSettle();
        final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
        final controller = home.controller;
        final player = controller.player;
        controller.queue.select(home.library.songs, 0);
        controller.toggleShuffle();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ActionChip, shortcut));
        await tester.pumpAndSettle();
        final local = tester.widget<LocalMusicScreen>(
          find.byType(LocalMusicScreen),
        );
        expect(identical(local.controller, controller), isTrue);
        expect(identical(local.controller.player, player), isTrue);
        expect(local.initialShowFolders, shortcut == 'Folders');
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        expect(find.byTooltip('Close player'), findsOneWidget);
        await back(tester, system);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(LocalMusicScreen), findsNothing);
        expect(controller.currentIndex, 0);
        expect(controller.currentSong!.id, 1);
        expect(
          identical(
            tester
                .widget<HomeScreen>(find.byType(HomeScreen))
                .controller
                .player,
            player,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(runtime.dispose);
        await tester.pumpAndSettle();
      });
    }

    testWidgets(
      'Library and Home retain independent folder stacks with $mode',
      (tester) async {
        await tester.pumpWidget((await tester.runAsync(() async => app()))!);
        await tester.pumpAndSettle();
        final player = tester
            .widget<HomeScreen>(find.byType(HomeScreen))
            .controller
            .player;
        await tester.tap(find.widgetWithText(ActionChip, 'Folders'));
        await tester.pumpAndSettle();
        await tab(tester, 'Library');
        expect(find.text('Your Library'), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(ListTile, 'Local Music'),
        );
        await tester.tap(find.widgetWithText(ListTile, 'Local Music'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Folders'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Music'));
        await tester.pumpAndSettle();
        expect(
          identical(
            tester
                .widget<LocalMusicFolderScreen>(
                  find.byType(LocalMusicFolderScreen),
                )
                .audioPlayer,
            player,
          ),
          isTrue,
        );
        await back(tester, system);
        expect(find.byType(LocalMusicScreen), findsOneWidget);
        expect(find.byType(LocalMusicFolderScreen), findsNothing);
        await back(tester, system);
        expect(find.text('Your Library'), findsOneWidget);
        await tab(tester, 'Home');
        expect(find.byType(LocalMusicScreen), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Folders'))
              .selected,
          isTrue,
        );
        await tester.tap(find.widgetWithText(ListTile, 'Music'));
        await tester.pumpAndSettle();
        await back(tester, system);
        expect(find.byType(LocalMusicScreen), findsOneWidget);
        await back(tester, system);
        expect(find.byType(HomeScreen), findsOneWidget);
        await tab(tester, 'Library');
        expect(find.text('Your Library'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(runtime.dispose);
        await tester.pumpAndSettle();
      },
    );
  }
}
