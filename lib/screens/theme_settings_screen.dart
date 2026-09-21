import 'package:flutter/material.dart';

import '../theme/melodify_theme.dart';
import '../theme/melodify_theme_controller.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key, required this.controller});

  final MelodifyThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Themes')),
        body: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: MelodifyThemeId.values.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final id = MelodifyThemeId.values[index];
              final preview = MelodifyTheme.paletteFor(id);
              final selected = controller.selected == id;
              return Card(
                child: Semantics(
                  selected: selected,
                  child: ListTile(
                    onTap: () => controller.select(id),
                    minVerticalPadding: 16,
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: preview.background,
                        border: Border.all(color: context.palette.muted),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: preview.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    title: Text(id.label),
                    subtitle: id == MelodifyThemeId.melodifyGreen
                        ? const Text('Current Melodify appearance')
                        : null,
                    trailing: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: context.palette.primary,
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
