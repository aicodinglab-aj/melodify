import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'melodify_theme.dart';

class MelodifyThemeController extends ChangeNotifier {
  MelodifyThemeController({this.preferences});

  static const preferenceKey = 'melodify_theme';
  final SharedPreferences? preferences;
  SharedPreferences? _loadedPreferences;
  MelodifyThemeId _selected = MelodifyThemeId.melodifyGreen;

  MelodifyThemeId get selected => _selected;
  ThemeData get theme => MelodifyTheme.forId(_selected);

  Future<void> restore() async {
    try {
      final store =
          _loadedPreferences ??
          preferences ??
          await SharedPreferences.getInstance();
      _loadedPreferences = store;
      _selected = MelodifyThemeId.fromStorage(store.getString(preferenceKey));
    } catch (_) {
      _selected = MelodifyThemeId.melodifyGreen;
    }
    notifyListeners();
  }

  Future<void> select(MelodifyThemeId id) async {
    if (_selected == id) return;
    _selected = id;
    notifyListeners();
    try {
      final store =
          _loadedPreferences ??
          preferences ??
          await SharedPreferences.getInstance();
      _loadedPreferences = store;
      await store.setString(preferenceKey, id.storageId);
    } catch (_) {
      // The chosen theme remains active for this session if storage fails.
    }
  }
}
