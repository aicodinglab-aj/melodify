import '../library/local_music_library.dart';

import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import '../theme/melodify_theme_controller.dart';

import '../theme/melodify_colors.dart';
import '../theme/melodify_theme.dart';
import '../widgets/music_artwork.dart';
import 'local_music_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.library,
    required this.themeController,
  });

  final PlaybackController controller;
  final LocalMusicLibrary library;
  final MelodifyThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Your Library',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SettingsScreen(themeController: themeController),
                    ),
                  ),
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A little closer to your music.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                const Chip(label: Text('Playlists')),
                // These remain presentation-only, matching the existing chips.
                // The current library view is represented by the Songs chip.
                Semantics(
                  selected: true,
                  child: Chip(
                    avatar: Icon(
                      Icons.music_note_rounded,
                      color: context.palette.background,
                      size: 18,
                    ),
                    backgroundColor: context.palette.primary,
                    label: const Text('Songs'),
                    labelStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(
                          color: context.palette.background,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const Chip(label: Text('Favorites')),
              ],
            ),
            const SizedBox(height: 28),
            Text('Your Music', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: MusicArtwork(
                  icon: Icons.favorite_rounded,
                  gradient: MelodifyColors.pinkArtwork,
                ),
                title: Text('Liked Songs'),
                subtitle: Text('Songs you have liked'),
              ),
            ),
            const SizedBox(height: 10),
            const Card(
              child: ListTile(
                leading: MusicArtwork(
                  icon: Icons.history_rounded,
                  gradient: MelodifyColors.duskArtwork,
                ),
                title: Text('Recently Played'),
                subtitle: Text('Music you played recently'),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const MusicArtwork(
                  icon: Icons.folder_rounded,
                  active: true,
                ),
                title: const Text('Local Music'),
                subtitle: const Text('Songs stored on your device'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => LocalMusicScreen(
                        controller: controller,
                        library: library,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
