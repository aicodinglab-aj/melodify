import 'package:flutter/material.dart';

abstract final class MelodifyColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const elevated = Color(0xFF282828);
  static const primary = Color(0xFF1DB954);
  static const darkGreen = Color(0xFF15A34A);
  static const highlight = Color(0xFF3BE477);
  static const text = Color(0xFFFFFFFF);
  static const secondaryText = Color(0xFFB3B3B3);
  static const muted = Color(0xFF535353);
  static const error = Color(0xFFFFB4AB);

  // Gradients are reserved for artwork, never the page background.
  static const greenArtwork = [Color(0xFF66E88F), primary];
  static const duskArtwork = [Color(0xFF7F5A3D), Color(0xFF3B82F6)];
  static const pinkArtwork = [Color(0xFFFF4D6D), Color(0xFF8B5CF6)];
  static const blueArtwork = [Color(0xFF38BDF8), Color(0xFF3B6CF6)];
}
