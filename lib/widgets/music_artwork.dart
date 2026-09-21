import 'package:flutter/material.dart';

import '../theme/melodify_theme.dart';

/// A lightweight placeholder shared by song rows, library items and the player.
class MusicArtwork extends StatelessWidget {
  const MusicArtwork({
    super.key,
    this.size = 48,
    this.icon = Icons.music_note_rounded,
    this.active = false,
    this.gradient,
  });

  final double size;
  final IconData icon;
  final bool active;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active
              ? context.palette.primary.withValues(alpha: 0.14)
              : context.palette.elevated,
          borderRadius: BorderRadius.circular(size > 64 ? 20 : 12),
          gradient: gradient == null
              ? null
              : LinearGradient(
                  colors: gradient!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        ),
        child: Icon(
          icon,
          size: size * 0.48,
          color: gradient != null
              ? context.palette.background
              : active
              ? context.palette.highlight
              : context.palette.secondaryText,
        ),
      ),
    );
  }
}
