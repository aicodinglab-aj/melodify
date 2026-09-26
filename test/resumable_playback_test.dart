import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melodify/library/local_music_library.dart';
import 'package:melodify/library/playback_history.dart';
import 'package:melodify/main.dart';
import 'package:melodify/playback/notification_settings.dart';
import 'package:melodify/playback/playback_controller.dart';
import 'package:melodify/playback/playback_queue.dart';
import 'package:melodify/playback/playback_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_playback_test.dart' show BackgroundRig, SessionPlayer;
import 'home_v1_test.dart' show flushEvents, HomeQuery;
import 'startup_playback_restoration_test.dart' show RestoreStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in PlaybackMode.values) {
    test(
      'hide and resume retains track/index/position/history in $mode',
      () async {
        final r = BackgroundRig();
        addTearDown(r.dispose);
        await r.select();
        await r.handler.skipToNext();
        r.controller.setMode(mode);
        await r.controller.seek(const Duration(seconds: 135));
        await flushEvents();
        final queue = List.of(r.controller.queue.items);
        final writes = r.store.writes;
        await r.controller.hidePlayer();
        await flushEvents();
        expect(r.player.playing, isFalse);
        expect(r.controller.currentSong!.id, 2);
        expect(r.controller.currentIndex, 1);
        expect(r.controller.queue.items, queue);
        expect(r.controller.mode, mode);
        expect(r.player.position, const Duration(seconds: 135));
        expect(r.controller.playerVisible, isFalse);
        expect(r.controller.canResume, isTrue);
        expect(
          r.handler.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        await r.controller.play();
        await flushEvents();
        expect(r.player.playing, isTrue);
        expect(r.controller.playerVisible, isTrue);
        expect(r.player.position, const Duration(seconds: 135));
        expect(r.controller.currentIndex, 1);
        expect(r.controller.queue.items, queue);
        expect(r.controller.mode, mode);
        expect(r.store.writes, writes);
      },
    );
  }

  test(
    'notification Close retains metadata and queue; reopen republishes both',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await r.controller.seek(const Duration(seconds: 135));
      final queues = <List<MediaItem>>[];
      final items = <MediaItem?>[];
      final q = r.handler.queue.listen(queues.add);
      final m = r.handler.mediaItem.listen(items.add);
      addTearDown(q.cancel);
      addTearDown(m.cancel);
      await r.handler.stop();
      await flushEvents();
      expect(r.handler.queue.value.length, 3);
      expect(r.handler.mediaItem.value!.id, 'path:/Music/1.mp3');
      expect(r.handler.playbackState.value.controls, isEmpty);
      final qCount = queues.length, mCount = items.length;
      await r.handler.play();
      await flushEvents();
      expect(queues.length, greaterThan(qCount));
      expect(items.length, greaterThan(mCount));
      expect(r.handler.playbackState.value.playing, isTrue);
      expect(
        r.handler.playbackState.value.updatePosition,
        const Duration(seconds: 135),
      );
      expect(r.handler.playbackState.value.controls, [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
        MediaControl.stop,
      ]);
      expect(r.handler.playbackState.value.androidCompactActionIndices, [
        0,
        1,
        2,
      ]);
    },
  );

  test(
    'explicit destructive clear still removes hidden resumable state',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      await r.controller.hidePlayer();
      await r.controller.close();
      expect(r.controller.currentSong, isNull);
      expect(r.controller.queue.items, isEmpty);
      expect(r.controller.canResume, isFalse);
      expect(r.controller.playerVisible, isFalse);
      await r.handler.play();
      expect(r.player.playing, isFalse);
    },
  );

  test('deleted hidden source fails safely and disables Home resume', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    await flushEvents();
    final history = List.of(r.store.data);
    await r.controller.hidePlayer();
    r.player.badPaths.add('/Music/1.mp3');
    await r.controller.play();
    await flushEvents();
    expect(r.player.playing, isFalse);
    expect(r.controller.canResume, isFalse);
    expect(r.controller.currentSong, isNull);
    expect(r.controller.playbackError, isNotNull);
    expect(r.store.data, history);
  });

  test('Close during delayed hidden resume prevents late playback', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    await r.controller.seek(const Duration(seconds: 135));
    await r.controller.hidePlayer();
    final gate = Completer<void>();
    r.player.gates['/Music/1.mp3'] = gate;
    final resume = r.controller.play();
    await flushEvents();
    await r.controller.hidePlayer();
    gate.complete();
    await resume;
    expect(r.player.playing, isFalse);
    await r.controller.play();
    await flushEvents();
    expect(r.player.position, const Duration(seconds: 135));
    expect(r.player.playing, isTrue);
  });

  test(
    'native source idle does not tear down a retained media session',
    () async {
      final r = BackgroundRig();
      addTearDown(r.dispose);
      await r.select();
      r.player.emit(false, ProcessingState.idle);
      await flushEvents();
      expect(
        r.handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(
        r.handler.playbackState.value.controls,
        contains(MediaControl.play),
      );
      await r.handler.play();
      await flushEvents();
      expect(r.handler.playbackState.value.playing, isTrue);
    },
  );

  test('hidden completion event cannot advance the saved queue', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    await r.select();
    await r.controller.hidePlayer();
    r.player.emit(false, ProcessingState.completed);
    await flushEvents();
    expect(r.controller.currentIndex, 0);
    expect(r.controller.playerVisible, isFalse);
  });

  testWidgets(
    'mini-player X hides, Home Play resumes same track at saved position',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      late SessionPlayer player;
      final runtime = (await tester.runAsync(() async {
        player = SessionPlayer();
        final history = PlaybackHistory(store: RestoreStore());
        return PlaybackRuntime(
          controller: PlaybackController(player, history: history),
          history: history,
          library: LocalMusicLibrary(query: HomeQuery()),
        );
      }))!;
      await tester.pumpWidget(MelodifyApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await runtime.controller.selectSong(
          runtime.library.songs,
          runtime.library.songs.last,
        );
        await runtime.controller.seek(const Duration(seconds: 135));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close player'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close player'), findsNothing);
      final play = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Play',
      );
      expect(tester.widget<IconButton>(play).onPressed, isNotNull);
      await tester.runAsync(() async {
        await tester.tap(play);
        await flushEvents();
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close player'), findsOneWidget);
      expect(player.playing, isTrue);
      expect(player.position, const Duration(seconds: 135));
      expect(runtime.controller.currentIndex, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(runtime.dispose);
    },
  );

  test(
    'blocked notification channel exposes settings and clears after unblocking',
    () async {
      const channel = MethodChannel('com.example.melodify/notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var blocked = true;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'isChannelBlocked' ? blocked : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final settings = NotificationSettings();
      addTearDown(settings.dispose);
      await settings.refresh();
      expect(settings.blocked.value, isTrue);
      await settings.open();
      blocked = false;
      await settings.refresh();
      expect(settings.blocked.value, isFalse);
      expect(calls, [
        'isChannelBlocked',
        'openChannelSettings',
        'isChannelBlocked',
      ]);
      // No permission prompt or repeated automatic settings launch.
    },
  );

  test(
    'notification settings platform failures do not escape into playback',
    () async {
      const channel = MethodChannel('com.example.melodify/notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final settings = NotificationSettings();
      addTearDown(settings.dispose);
      await settings.refresh();
      await settings.open();
      expect(settings.blocked.value, isFalse);
    },
  );
}
