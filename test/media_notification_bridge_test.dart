import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_service_platform_interface/method_channel_audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'background_playback_test.dart' show BackgroundRig;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native media bridge receives playing metadata, controls and reopened session', () async {
    AudioServicePlatform.instance = MethodChannelAudioService();
    const client = MethodChannel('com.ryanheise.audio_service.client.methods');
    const handler = MethodChannel(
      'com.ryanheise.audio_service.handler.methods',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final cacheRoot = await Directory.systemTemp.createTemp(
      'melodify-media-test-',
    );
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => cacheRoot.path);
    addTearDown(() async {
      await AudioService.cacheManager.dispose();
      messenger.setMockMethodCallHandler(paths, null);
      await cacheRoot.delete(recursive: true);
    });
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(client, (_) async => null);
    messenger.setMockMethodCallHandler(handler, (call) async {
      calls.add(call);
      return null;
    });
    final r = BackgroundRig();
    await AudioService.init(
      builder: () => r.handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.melodify.playback',
        androidNotificationChannelName: 'Music playback',
        androidStopForegroundOnPause: false,
        androidResumeOnClick: false,
        androidNotificationIcon: 'drawable/ic_stat_music',
      ),
    );
    await r.select();
    Map<dynamic, dynamic> state() =>
        (calls.lastWhere((c) => c.method == 'setState').arguments
                as Map)['state']
            as Map;
    await waitUntil(
      () =>
          calls.any((c) => c.method == 'setState') &&
          state()['playing'] == true,
    );
    expect(state()['playing'], isTrue);
    expect(state()['processingState'], AudioProcessingState.ready.index);
    expect((state()['controls'] as List).length, 4);
    expect(state()['androidCompactActionIndices'], [0, 1, 2]);
    expect(calls.any((c) => c.method == 'setMediaItem'), isTrue);
    expect(calls.any((c) => c.method == 'setQueue'), isTrue);
    await r.handler.stop();
    await waitUntil(
      () =>
          calls.any((c) => c.method == 'stopService') &&
          state()['playing'] == false,
    );
    expect(state()['playing'], isFalse);
    expect(state()['processingState'], AudioProcessingState.idle.index);
    expect(calls.any((c) => c.method == 'stopService'), isTrue);
    final count = calls.length;
    await r.handler.play();
    await waitUntil(
      () =>
          state()['playing'] == true &&
          calls.skip(count).any((c) => c.method == 'setMediaItem') &&
          calls.skip(count).any((c) => c.method == 'setQueue'),
    );
    expect(state()['playing'], isTrue);
    expect(calls.skip(count).any((c) => c.method == 'setMediaItem'), isTrue);
    expect(calls.skip(count).any((c) => c.method == 'setQueue'), isTrue);
    await r.dispose();
    messenger.setMockMethodCallHandler(client, null);
    messenger.setMockMethodCallHandler(handler, null);
  });
}

Future<void> waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Native method-channel publication did not complete',
  );
}
