import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'playback_controller.dart';

/// The only interruption/noisy-output policy; just_audio's automatic handling
/// is disabled on the production player to avoid duplicate pause/resume paths.
class PlaybackInterruptions {
  PlaybackInterruptions(
    this.controller, {
    required Stream<AudioInterruptionEvent> interruptions,
    required Stream<void> becomingNoisy,
  }) {
    _subscriptions = [
      interruptions.listen((event) => _run(() => handle(event))),
      becomingNoisy.listen((_) => _run(disconnect)),
    ];
  }

  final PlaybackController controller;
  late final List<StreamSubscription<dynamic>> _subscriptions;
  int? _interruptedRevision;
  bool _resume = false;
  bool _disposed = false;
  int _eventRevision = 0;
  Future<void> _pause = Future.value();

  void _run(Future<void> Function() action) {
    unawaited(
      action().catchError((Object _) {
        if (!_disposed) controller.reportSystemError();
      }),
    );
  }

  Future<void> handle(AudioInterruptionEvent event) async {
    if (_disposed) return;
    final eventRevision = ++_eventRevision;
    if (event.begin) {
      if (_interruptedRevision == null) {
        _interruptedRevision = controller.userActionRevision;
        _resume = controller.player.playing || controller.wantsPlayback;
      }
      if (event.type == AudioInterruptionType.unknown) _resume = false;
      // Music configuration requests pause rather than ducking. Also pause if a
      // platform delivers duck anyway; never unexpectedly route loud audio.
      _pause = controller.pause(userInitiated: false);
      await _pause;
    } else {
      final revision = _interruptedRevision;
      final resume = _resume && event.type != AudioInterruptionType.unknown;
      _interruptedRevision = null;
      _resume = false;
      await _pause;
      if (!_disposed &&
          eventRevision == _eventRevision &&
          resume &&
          revision == controller.userActionRevision) {
        await controller.play(userInitiated: false);
      }
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _eventRevision++;
    _resume = false;
    _interruptedRevision = null;
    await controller.pause();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
