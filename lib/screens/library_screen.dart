import 'playlists_screen.dart';
import '../library/playlists.dart';
import 'liked_songs_screen.dart';
import '../library/favorites.dart';
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
    this.playlists,
    this.favorites,
    required this.controller,
    required this.library,
    required this.themeController,
  });

  final Playlists? playlists;
  final Favorites? favorites;
  final PlaybackController controller;
  final LocalMusicLibrary library;
  final MelodifyThemeController themeController;

  void _openPlaylists(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistsScreen(
        playlists: playlists!,
        library: library,
        controller: controller,
        favorites: favorites,
      ),
    ),
  );

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
                ActionChip(
                  label: const Text('Playlists'),
                  onPressed: playlists == null
                      ? null
                      : () => _openPlaylists(context),
                ),
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
            Card(
              child: ListTile(
                onTap: favorites == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LikedSongsScreen(
                            controller: controller,
                            library: library,
                            favorites: favorites!,
                            playlists: playlists,
                          ),
                        ),
                      ),
                trailing: const Icon(Icons.chevron_right_rounded),
                leading: const MusicArtwork(
                  icon: Icons.favorite_rounded,
                  gradient: MelodifyColors.pinkArtwork,
                ),
                title: const Text('Liked Songs'),
                subtitle: const Text('Songs you have liked'),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const MusicArtwork(
                  icon: Icons.queue_music_rounded,
                  active: true,
                ),
                title: const Text('Playlists'),
                subtitle: const Text('Music organized by you'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: playlists == null ? null : () => _openPlaylists(context),
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
                        favorites: favorites,
                        playlists: playlists,
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
