import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/playback/playback_queue.dart';

void main() {
  test('Songs and folder selections retain their displayed queue', () {
    final queue = PlaybackQueue<String>();
    queue.select(['A', 'B', 'C'], 1);
    expect(queue.items, ['A', 'B', 'C']);
    expect(queue.current, 'B');
    expect(queue.index, 1);
    queue.select(['Folder A', 'Folder B'], 0);
    expect(queue.items, ['Folder A', 'Folder B']);
    expect(queue.current, 'Folder A');
  });

  test('sequential next stops at end and previous moves back', () {
    final queue = PlaybackQueue<String>()..select(['A', 'B'], 0);
    expect(queue.next(), 1);
    expect(queue.next(automatic: true), isNull);
    expect(queue.current, 'B');
    expect(queue.previous(), 0);
  });

  test('repeat one repeats automatically but manual next advances', () {
    final queue = PlaybackQueue<String>()..select(['A', 'B'], 0);
    queue.mode = PlaybackMode.repeatOne;
    expect(queue.next(automatic: true), 0);
    expect(queue.next(), 1);
  });

  test('repeat all wraps in both directions', () {
    final queue = PlaybackQueue<String>()..select(['A', 'B'], 1);
    queue.mode = PlaybackMode.repeatAll;
    expect(queue.next(automatic: true), 0);
    expect(queue.previous(), 1);
  });

  test('shuffle avoids immediate replay and previous follows history', () {
    final queue = PlaybackQueue<String>(random: Random(7))
      ..select(['A', 'B', 'C'], 0);
    queue.mode = PlaybackMode.shuffle;
    final first = queue.next()!;
    expect(first, isNot(0));
    final second = queue.next()!;
    expect(second, isNot(first));
    expect(queue.previous(), first);
    expect(queue.next(), second);
    queue.clear();
    expect(queue.items, isEmpty);
    expect(queue.current, isNull);
    expect(queue.index, -1);
  });
}
