import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'background_playback_test.dart' show BackgroundRig;
import 'home_v1_test.dart' show flushEvents, song;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all published Android controls have existing drawable icons protected from shrinking', () async {
    final r = BackgroundRig();
    addTearDown(r.dispose);
    final states = <PlaybackState>[];
    final subscription = r.handler.playbackState.listen(states.add);
    addTearDown(subscription.cancel);
    await r.controller.restoreRecentSongs([song(1), song(2)]);
    await r.handler.play();
    await flushEvents();
    await r.handler.pause();
    await r.handler.stop();
    await r.handler.play();
    await flushEvents();

    final controls = states.expand((state) => state.controls).toSet();
    expect(controls.map((control) => control.action).toSet(), {
      MediaAction.skipToPrevious,
      MediaAction.play,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.stop,
    });
    final configFile = File('.dart_tool/package_config.json');
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final package = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((package) => package['name'] == 'audio_service');
    final packageRoot = Directory.fromUri(
      configFile.absolute.uri.resolve(package['rootUri'] as String),
    ).uri;
    final resourceRoots = [
      Directory('android/app/src/main/res'),
      Directory.fromUri(packageRoot.resolve('android/src/main/res/')),
    ];
    final keep = File('android/app/src/main/res/raw/keep.xml')
        .readAsStringSync();
    final kept = RegExp(r'tools:keep="([^"]+)"')
        .firstMatch(keep)!
        .group(1)!
        .split(',')
        .map((value) => value.trim())
        .toSet();
    for (final control in controls) {
      // Even the standard Stop becomes a native CustomAction on Android 13+.
      expect(
        control.customAction,
        isNull,
        reason: 'Standard transport must stay standard',
      );
      expect(
        control.androidIcon,
        matches(RegExp(r'^drawable/[a-z][a-z0-9_]*$')),
      );
      final name = control.androidIcon.split('/').last;
      final exists = resourceRoots.any(
        (root) => root
            .listSync(recursive: true)
            .whereType<File>()
            .any(
              (file) =>
                  file.parent.uri.pathSegments
                      .where((p) => p.isNotEmpty)
                      .last
                      .startsWith('drawable') &&
                  file.uri.pathSegments.last.split('.').first == name,
            ),
      );
      expect(
        exists,
        isTrue,
        reason: '${control.action} must resolve to a drawable',
      );
      expect(
        kept,
        contains('@${control.androidIcon}'),
        reason:
            '${control.action} is looked up dynamically and must survive shrinking',
      );
    }
    expect(kept, contains('@drawable/ic_stat_music'));
    expect(r.controller.canResume, isTrue);
  });
}
