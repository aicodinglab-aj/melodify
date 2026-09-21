import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/screens/about_screen.dart';
import 'package:melodify/theme/melodify_theme.dart';

void main() {
  testWidgets('About opens Flutter license page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: MelodifyTheme.dark, home: const AboutScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Source Licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
