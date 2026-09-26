import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/playback_history.dart';
import 'package:melodify/main.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_queue.dart';
import 'package:melodify/playback/playback_runtime.dart';
import 'package:melodify/screens/now_playing_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_playback_test.dart' show SessionPlayer;
import 'home_v1_test.dart' show HomeQuery, song, flushEvents;
import 'startup_playback_restoration_test.dart' show RestoreStore;

final mini = find.byKey(const ValueKey('shared-mini-player'));
Finder button(String tooltip) => find.descendant(
  of: mini,
  matching: find.byWidgetPredicate(
    (w) => w is IconButton && w.tooltip == tooltip,
  ),
);

Future<PlaybackRuntime> mount(
  WidgetTester tester, {
  bool recent = false,
  MelodifyThemeId theme = MelodifyThemeId.melodifyGreen,
}) async {
  SharedPreferences.setMockInitialValues({'melodify_theme': theme.storageId});
  final runtime = (await tester.runAsync(() async {
    final store = RestoreStore();
    if (recent) store.data = ['path:/Music/1.mp3'];
    final history = PlaybackHistory(store: store);
    final runtime = PlaybackRuntime(
      controller: PlaybackController(
        SessionPlayer()..lastSeek = Duration.zero,
        history: history,
      ),
      history: history,
      library: LocalMusicLibrary(query: HomeQuery()),
    );
    await runtime.start();
    return runtime;
  }))!;
  await tester.pumpWidget(MelodifyApp(runtime: runtime));
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> finish(WidgetTester tester, PlaybackRuntime runtime) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(runtime.dispose);
}

void main() {
  testWidgets(
    'restored song stays hidden across startup tabs; Home Play reveals it without reloading',
    (tester) async {
      final runtime = await mount(tester, recent: true);
      final player = runtime.controller.player as SessionPlayer;
      final attempts = player.attempted.length;
      expect(runtime.controller.currentSong!.id, 1);
      expect(runtime.controller.canResume, isTrue);
      expect(player.playing, isFalse);
      for (final tab in ['Search', 'Library', 'Home']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(tab),
          ),
        );
        await tester.pumpAndSettle();
        expect(mini, findsNothing);
      }
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Play'));
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(mini, findsOneWidget);
      expect(player.playing, isTrue);
      expect(player.attempted.length, attempts);
      expect(runtime.controller.currentSong!.id, 1);
      await finish(tester, runtime);
    },
  );

  testWidgets(
    'shared mini transports delegate and only information opens Now Playing',
    (tester) async {
      final runtime = await mount(tester);
      final c = runtime.controller;
      final player = c.player as SessionPlayer;
      await tester.runAsync(
        () => c.selectSong(runtime.library.songs, runtime.library.songs.first),
      );
      await tester.pumpAndSettle();
      for (final label in ['Previous', 'Pause', 'Next', 'Close player']) {
        expect(button(label), findsOneWidget);
      }
      await tester.runAsync(() async {
        await tester.tap(button('Next'));
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(c.currentIndex, 1);
      expect(runtime.handler.mediaItem.value!.id, 'path:/Music/2.mp3');
      expect(tester.widget<IconButton>(button('Next')).onPressed, isNull);
      expect(find.byType(NowPlayingScreen), findsNothing);
      await tester.runAsync(() async {
        await c.seek(const Duration(seconds: 4));
        await tester.tap(button('Previous'));
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(c.currentIndex, 1);
      expect(player.position, Duration.zero);
      await tester.runAsync(() async {
        await tester.tap(button('Previous'));
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(c.currentIndex, 0);
      await tester.runAsync(() async {
        await tester.tap(button('Pause'));
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      expect(runtime.handler.playbackState.value.playing, isFalse);
      await tester.runAsync(runtime.handler.play);
      await tester.pumpAndSettle();
      expect(button('Pause'), findsOneWidget);
      await tester.runAsync(runtime.handler.skipToNext);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: mini, matching: find.text('Song 2')),
        findsOneWidget,
      );
      expect(find.byType(NowPlayingScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mini-player-information')));
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await c.seek(const Duration(seconds: 135));
        await tester.tap(button('Close player'));
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(mini, findsNothing);
      expect(c.currentIndex, 1);
      expect(c.queue.items.length, 2);
      expect(c.canResume, isTrue);
      expect(player.position, const Duration(seconds: 135));
      await finish(tester, runtime);
    },
  );

  test('transport availability matches manual queue semantics without mutating state', () {
    final queue = PlaybackQueue<int>();
    expect(queue.canNext, isFalse);
    expect(queue.canPrevious, isFalse);
    queue.select([1], 0);
    for (final mode in PlaybackMode.values) {
      queue.mode = mode;
      expect(
        queue.canNext,
        mode == PlaybackMode.shuffle || mode == PlaybackMode.repeatAll,
      );
      expect(queue.canPrevious, isTrue);
      expect(queue.index, 0);
    }
    queue.mode = PlaybackMode.repeatOne;
    queue.select([1, 2], 0);
    expect(queue.canNext, isTrue);
    queue.next();
    expect(queue.canNext, isFalse);
  });

  for (final theme in MelodifyThemeId.values) {
    testWidgets(
      'mini-player at 280px keeps controls and theme in ${theme.name}',
      (tester) async {
        tester.view.physicalSize = const Size(280, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final runtime = await mount(tester, theme: theme);
        final long = song(
          7,
          title: 'A very long song title that must be ellipsized',
        );
        await tester.runAsync(
          () => runtime.controller.selectSong([long], long),
        );
        await tester.pumpAndSettle();
        for (final label in ['Previous', 'Pause', 'Next', 'Close player']) {
          expect(button(label), findsOneWidget);
          expect(tester.getSize(button(label)).width, greaterThanOrEqualTo(48));
        }
        final context = tester.element(mini);
        final pause = tester.widget<IconButton>(button('Pause'));
        expect(
          pause.style!.backgroundColor!.resolve({}),
          context.palette.primary,
        );
        expect(
          find.descendant(of: mini, matching: find.text(long.title)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await finish(tester, runtime);
      },
    );
  }
}
