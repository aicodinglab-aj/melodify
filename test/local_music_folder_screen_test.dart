import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melodify/models/local_music_folder.dart';
import 'package:melodify/screens/local_music_folder_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

// A read-only test double; no native AudioPlayer is constructed.
class _PlayerView extends Fake implements AudioPlayer {
  bool disposed = false;

  @override
  PlayerState get playerState => PlayerState(false, ProcessingState.ready);
  @override
  Stream<PlayerState> get playerStateStream => Stream.value(playerState);
  @override
  AudioSource? get audioSource => null;
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  testWidgets(
    'folder selection delegates playback, prevents overlapping loads, and safely pops',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = _PlayerView();
      final first = SongModel({
        '_id': 1,
        '_data': '/Music/English/a.mp3',
        'title': 'First song',
        'artist': 'Artist',
        'duration': 185000,
      });
      final second = SongModel({
        '_id': 2,
        '_data': '/Music/English/b.mp3',
        'title':
            'A long song title that needs to truncate gracefully on a phone',
        'artist': '<unknown>',
        'duration': null,
      });
      final pending = Completer<void>();
      final selected = <SongModel>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: MelodifyTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalMusicFolderScreen(
                      folder: LocalMusicFolder(
                        path: '/Music/English',
                        songs: [first, second],
                      ),
                      audioPlayer: player,
                      onPlaySong: (song) {
                        selected.add(song);
                        return pending.future;
                      },
                    ),
                  ),
                ),
                child: const Text('Open folder'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      expect(find.text('/Music/English'), findsOneWidget);
      expect(find.text('3:05'), findsOneWidget);
      expect(find.text('Local Music'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('First song'));
      await tester.pump();
      await tester.tap(find.text(second.title));
      await tester.pump();
      expect(selected, [first]);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open folder'), findsOneWidget);
      expect(player.disposed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
