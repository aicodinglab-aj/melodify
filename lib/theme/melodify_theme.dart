import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'melodify_colors.dart';

enum MelodifyThemeId {
  melodifyGreen('melodifyGreen', 'Melodify Green'),
  oceanBlue('oceanBlue', 'Ocean Blue'),
  purpleNight('purpleNight', 'Purple Night'),
  crimson('crimson', 'Crimson'),
  amoledBlack('amoledBlack', 'AMOLED Black'),
  light('light', 'Light');

  const MelodifyThemeId(this.storageId, this.label);
  final String storageId;
  final String label;

  static MelodifyThemeId fromStorage(String? value) {
    for (final id in values) {
      if (id.storageId == value) return id;
    }
    return melodifyGreen;
  }
}

@immutable
class MelodifyPalette extends ThemeExtension<MelodifyPalette> {
  const MelodifyPalette(
    this.background,
    this.surface,
    this.elevated,
    this.primary,
    this.highlight,
    this.text,
    this.secondaryText,
    this.muted,
  );

  final Color background, surface, elevated, primary, highlight;
  final Color text, secondaryText, muted;

  @override
  MelodifyPalette copyWith({
    Color? background,
    Color? surface,
    Color? elevated,
    Color? primary,
    Color? highlight,
    Color? text,
    Color? secondaryText,
    Color? muted,
  }) => MelodifyPalette(
    background ?? this.background,
    surface ?? this.surface,
    elevated ?? this.elevated,
    primary ?? this.primary,
    highlight ?? this.highlight,
    text ?? this.text,
    secondaryText ?? this.secondaryText,
    muted ?? this.muted,
  );

  @override
  MelodifyPalette lerp(ThemeExtension<MelodifyPalette>? other, double t) {
    if (other is! MelodifyPalette) return this;
    return MelodifyPalette(
      Color.lerp(background, other.background, t)!,
      Color.lerp(surface, other.surface, t)!,
      Color.lerp(elevated, other.elevated, t)!,
      Color.lerp(primary, other.primary, t)!,
      Color.lerp(highlight, other.highlight, t)!,
      Color.lerp(text, other.text, t)!,
      Color.lerp(secondaryText, other.secondaryText, t)!,
      Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension MelodifyThemeContext on BuildContext {
  MelodifyPalette get palette => Theme.of(this).extension<MelodifyPalette>()!;
}

abstract final class MelodifyTheme {
  static const _green = MelodifyPalette(
    MelodifyColors.background,
    MelodifyColors.surface,
    MelodifyColors.elevated,
    MelodifyColors.primary,
    MelodifyColors.highlight,
    MelodifyColors.text,
    MelodifyColors.secondaryText,
    MelodifyColors.muted,
  );

  static MelodifyPalette paletteFor(MelodifyThemeId id) => switch (id) {
    MelodifyThemeId.melodifyGreen => _green,
    MelodifyThemeId.oceanBlue => const MelodifyPalette(
      Color(0xFF081422),
      Color(0xFF102237),
      Color(0xFF19314B),
      Color(0xFF4DA8FF),
      Color(0xFF79C2FF),
      Colors.white,
      Color(0xFFAEC2D5),
      Color(0xFF58718A),
    ),
    MelodifyThemeId.purpleNight => const MelodifyPalette(
      Color(0xFF110D19),
      Color(0xFF20172C),
      Color(0xFF2E223E),
      Color(0xFFAD76F6),
      Color(0xFFC79AFF),
      Colors.white,
      Color(0xFFC3B5D0),
      Color(0xFF71617F),
    ),
    MelodifyThemeId.crimson => const MelodifyPalette(
      Color(0xFF171214),
      Color(0xFF251D20),
      Color(0xFF35272C),
      Color(0xFFE94D70),
      Color(0xFFFF7996),
      Colors.white,
      Color(0xFFC9B7BC),
      Color(0xFF786169),
    ),
    MelodifyThemeId.amoledBlack => const MelodifyPalette(
      Colors.black,
      Color(0xFF101010),
      Color(0xFF1C1C1C),
      MelodifyColors.primary,
      MelodifyColors.highlight,
      Colors.white,
      MelodifyColors.secondaryText,
      MelodifyColors.muted,
    ),
    MelodifyThemeId.light => const MelodifyPalette(
      Color(0xFFF7F9F7),
      Colors.white,
      Color(0xFFE9EFEA),
      Color(0xFF147D3B),
      Color(0xFF116C34),
      Color(0xFF17211A),
      Color(0xFF526159),
      Color(0xFFB4C1B8),
    ),
  };

  static ThemeData get dark => forId(MelodifyThemeId.melodifyGreen);

  static ThemeData forId(MelodifyThemeId id) {
    final p = paletteFor(id);
    final light = id == MelodifyThemeId.light;
    final colors = ColorScheme(
      brightness: light ? Brightness.light : Brightness.dark,
      primary: p.primary,
      onPrimary: p.background,
      secondary: p.highlight,
      onSecondary: p.background,
      error: light ? const Color(0xFFB3261E) : MelodifyColors.error,
      onError: light ? Colors.white : p.text,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.secondaryText,
      surfaceContainerHighest: p.elevated,
      outline: p.muted,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final text = base.textTheme.copyWith(
      headlineLarge: TextStyle(
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        color: p.text,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: p.text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: p.secondaryText),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: p.secondaryText),
    );
    return base.copyWith(
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.elevated,
        hintStyle: text.bodyMedium,
        prefixIconColor: p.secondaryText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.primary),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.elevated,
        selectedColor: p.primary,
        labelStyle: text.labelLarge?.copyWith(color: p.text),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        iconColor: p.secondaryText,
        textColor: p.text,
        selectedColor: p.highlight,
        selectedTileColor: p.primary.withValues(alpha: 0.08),
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: p.primary.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? p.highlight
                : p.secondaryText,
            size: 25,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? p.text
                : p.secondaryText,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.muted,
        thumbColor: p.highlight,
        overlayColor: p.primary.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.background,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.muted.withValues(alpha: 0.25),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.elevated,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
