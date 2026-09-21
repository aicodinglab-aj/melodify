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

  for (final system in [false, true]) {
    final mode = system ? 'system Back' : 'AppBar Back';
    for (final shortcut in ['Local Music', 'Songs', 'Folders']) {
      testWidgets('Home -> $shortcut -> $mode returns to Home', (tester) async {
        await tester.pumpWidget(const MelodifyApp());
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
        await tester.pumpAndSettle();
      });
    }

    testWidgets(
      'Library and Home retain independent folder stacks with $mode',
      (tester) async {
        await tester.pumpWidget(const MelodifyApp());
        await tester.pumpAndSettle();
        final player = tester
            .widget<HomeScreen>(find.byType(HomeScreen))
            .controller
            .player;
        await tester.tap(find.widgetWithText(ActionChip, 'Folders'));
        await tester.pumpAndSettle();
        await tab(tester, 'Library');
        expect(find.text('Your Library'), findsOneWidget);
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
        await tester.pumpAndSettle();
      },
    );
  }
}
