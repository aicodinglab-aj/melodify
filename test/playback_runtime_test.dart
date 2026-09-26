import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_service_platform_interface/method_channel_audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/playback/playback_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent initialization registers one service and shares one player without autoplay', () async {
    SharedPreferences.setMockInitialValues({});
    AudioServicePlatform.instance = MethodChannelAudioService();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var registrations = 0;
    const client = MethodChannel('com.ryanheise.audio_service.client.methods');
    const handler = MethodChannel(
      'com.ryanheise.audio_service.handler.methods',
    );
    const session = MethodChannel('com.ryanheise.audio_session');
    const audio = MethodChannel('com.ryanheise.just_audio.methods');
    messenger.setMockMethodCallHandler(client, (call) async {
      if (call.method == 'configure') registrations++;
      return null;
    });
    messenger.setMockMethodCallHandler(handler, (_) async => null);
    messenger.setMockMethodCallHandler(session, (_) async => null);
    messenger.setMockMethodCallHandler(audio, (_) async => <String, dynamic>{});
    final first = PlaybackRuntime.initialize();
    final second = PlaybackRuntime.initialize();
    expect(identical(first, second), isTrue);
    final runtime = await first;
    expect(identical(runtime, await second), isTrue);
    expect(
      identical(runtime.controller.player, runtime.handler.controller.player),
      isTrue,
    );
    expect(registrations, 1);
    expect(runtime.backgroundIssue.value, isNull);
    expect(runtime.controller.player.playing, isFalse);
    expect(runtime.controller.currentSong, isNull);
    expect(runtime.handler.queue.value, isEmpty);
    await runtime.dispose();
    for (final channel in [client, handler, session, audio]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
