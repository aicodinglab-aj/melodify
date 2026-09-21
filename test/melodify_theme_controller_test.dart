import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:melodify/theme/melodify_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('green is default and invalid stored ID falls back to green', () async {
    SharedPreferences.setMockInitialValues({});
    final first = MelodifyThemeController();
    await first.restore();
    expect(first.selected, MelodifyThemeId.melodifyGreen);
    expect(first.theme.scaffoldBackgroundColor, const Color(0xFF121212));
    first.dispose();

    SharedPreferences.setMockInitialValues({
      MelodifyThemeController.preferenceKey: 'unknown-theme',
    });
    final invalid = MelodifyThemeController();
    await invalid.restore();
    expect(invalid.selected, MelodifyThemeId.melodifyGreen);
    invalid.dispose();
  });

  test('selection persists by stable ID and restores', () async {
    SharedPreferences.setMockInitialValues({});
    final first = MelodifyThemeController();
    await first.restore();
    await first.select(MelodifyThemeId.oceanBlue);
    expect(first.selected, MelodifyThemeId.oceanBlue);
    final store = await SharedPreferences.getInstance();
    expect(store.getString(MelodifyThemeController.preferenceKey), 'oceanBlue');
    final second = MelodifyThemeController();
    await second.restore();
    expect(second.selected, MelodifyThemeId.oceanBlue);
    first.dispose();
    second.dispose();
  });

  test('all six themes have distinct palettes and AMOLED is true black', () {
    expect(MelodifyThemeId.values, hasLength(6));
    final accents = MelodifyThemeId.values
        .map((id) => MelodifyTheme.paletteFor(id).primary)
        .toSet();
    expect(accents.length, greaterThanOrEqualTo(4));
    expect(
      MelodifyTheme.forId(MelodifyThemeId.amoledBlack).scaffoldBackgroundColor,
      Colors.black,
    );
    expect(
      MelodifyTheme.forId(MelodifyThemeId.light).brightness,
      Brightness.light,
    );
  });

  test('every listed theme can be selected and stored', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = MelodifyThemeController();
    await controller.restore();
    for (final id in MelodifyThemeId.values) {
      await controller.select(id);
      expect(controller.selected, id);
      expect(
        controller.theme.extension<MelodifyPalette>()!.primary,
        MelodifyTheme.paletteFor(id).primary,
      );
    }
    final store = await SharedPreferences.getInstance();
    expect(
      store.getString(MelodifyThemeController.preferenceKey),
      MelodifyThemeId.light.storageId,
    );
    controller.dispose();
  });
}
