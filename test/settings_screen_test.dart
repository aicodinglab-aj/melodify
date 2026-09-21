import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/screens/settings_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';
import 'package:melodify/theme/melodify_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Settings opens Themes and selection applies immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final controller = MelodifyThemeController();
    await controller.restore();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MaterialApp(
          theme: controller.theme,
          home: SettingsScreen(themeController: controller),
        ),
      ),
    );
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('Themes'), findsOneWidget);
    await tester.tap(find.text('Ocean Blue'));
    await tester.pumpAndSettle();
    expect(controller.selected, MelodifyThemeId.oceanBlue);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings opens About with bundled version and licenses entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = MelodifyThemeController();
    await controller.restore();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MelodifyTheme.dark,
        home: SettingsScreen(themeController: controller),
      ),
    );

    expect(find.text('APP'), findsOneWidget);
    await tester.tap(find.text('About Melodify'));
    await tester.pumpAndSettle();

    expect(find.text('Melodify'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'Version \d+\.\d+\.\d+')),
      findsOneWidget,
    );
    expect(
      find.text('A personal music player for your local music library.'),
      findsOneWidget,
    );
    expect(find.text('Developed by DMJ Labs'), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });
}
