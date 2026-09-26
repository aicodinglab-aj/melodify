import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read-only channel status; media-session notifications do not require an
/// Android 13 POST_NOTIFICATIONS prompt. A blocked channel needs user settings.
class NotificationSettings {
  static const channelId = 'com.example.melodify.playback';
  static const _channel = MethodChannel('com.example.melodify/notifications');
  final blocked = ValueNotifier(false);
  bool _disposed = false;

  Future<void> refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final value = await _channel.invokeMethod<bool>('isChannelBlocked');
      if (!_disposed) blocked.value = value ?? false;
    } on PlatformException {
      // Inspection must never interfere with playback.
    } on MissingPluginException {
      // Unsupported platforms and widget hosts have no Android channel.
    }
  }

  Future<void> open() async {
    try {
      await _channel.invokeMethod<void>('openChannelSettings');
    } on PlatformException {
      // Some OEMs do not expose the settings activity.
    } on MissingPluginException {
      // No settings activity on non-Android hosts.
    }
  }

  void dispose() {
    _disposed = true;
    blocked.dispose();
  }
}
