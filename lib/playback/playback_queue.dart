import 'dart:math';

enum PlaybackMode { sequential, repeatAll, repeatOne, shuffle }

/// Queue order and shuffle history, independent of the audio backend.
class PlaybackQueue<T> {
  PlaybackQueue({Random? random}) : _random = random ?? Random();

  final Random _random;
  List<T> _items = [];
  final List<int> _history = [];
  int _historyPosition = -1;
  int _index = -1;
  PlaybackMode mode = PlaybackMode.sequential;

  List<T> get items => List.unmodifiable(_items);
  int get index => _index;
  T? get current => _index < 0 ? null : _items[_index];
  bool get isEmpty => _items.isEmpty;

  void select(List<T> items, int index) {
    if (index < 0 || index >= items.length) {
      throw RangeError.index(index, items);
    }
    _items = List.of(items);
    _index = index;
    _history
      ..clear()
      ..add(index);
    _historyPosition = 0;
  }

  void clear() {
    _items = [];
    _index = -1;
    _history.clear();
    _historyPosition = -1;
  }

  int? next({bool automatic = false}) {
    if (isEmpty) return null;
    if (automatic && mode == PlaybackMode.repeatOne) return _index;
    if (mode == PlaybackMode.shuffle) {
      if (_historyPosition + 1 < _history.length) {
        _index = _history[++_historyPosition];
      } else if (_items.length > 1) {
        final draw = _random.nextInt(_items.length - 1);
        _index = draw >= _index ? draw + 1 : draw;
        _history.add(_index);
        _historyPosition++;
      }
      return _index;
    }
    if (_index + 1 < _items.length) return ++_index;
    if (mode == PlaybackMode.repeatAll) return _index = 0;
    return null;
  }

  int? previous() {
    if (isEmpty) return null;
    if (mode == PlaybackMode.shuffle) {
      if (_historyPosition > 0) _index = _history[--_historyPosition];
      return _index;
    }
    if (_index > 0) return --_index;
    if (mode == PlaybackMode.repeatAll) return _index = _items.length - 1;
    return _index;
  }
}
