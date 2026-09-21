import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';

import '../theme/melodify_colors.dart';
import '../theme/melodify_theme.dart';
import '../widgets/music_artwork.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final PlaybackController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const MusicArtwork(
                  size: 40,
                  icon: Icons.graphic_eq_rounded,
                  active: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Melodify',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Good evening', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 32),
            Text(
              'Recently Played',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final singleColumn =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(14) > 22;
                final width = singleColumn
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 14) / 2;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: width,
                      child: _buildMusicCard(
                        'Recently Played One',
                        MelodifyColors.duskArtwork,
                        Icons.album_rounded,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _buildMusicCard(
                        'Recently Played Two',
                        MelodifyColors.blueArtwork,
                        Icons.graphic_eq_rounded,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Your Music',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                StreamBuilder<bool>(
                  stream: widget.controller.player.playingStream,
                  initialData: widget.controller.player.playing,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? false;

                    return IconButton.filled(
                      onPressed: widget.controller.currentSong == null
                          ? null
                          : widget.controller.togglePlayback,
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      style: IconButton.styleFrom(
                        backgroundColor: context.palette.primary,
                        foregroundColor: context.palette.background,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _buildSongRow('Song One'),
                  _buildSongRow('Song Two'),
                  _buildSongRow('Song Three'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicCard(String title, List<Color> gradient, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: LayoutBuilder(
                builder: (context, constraints) => MusicArtwork(
                  size: constraints.maxWidth,
                  icon: icon,
                  gradient: gradient,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Your rotation', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildSongRow(String title) {
    return ListTile(
      leading: const MusicArtwork(),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('Artist Name'),
      trailing: const Icon(Icons.more_vert),
    );
  }
}
