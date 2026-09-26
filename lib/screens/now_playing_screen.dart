import '../widgets/favorite_button.dart';
import '../library/favorites.dart';

import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import '../playback/playback_queue.dart';
import '../theme/melodify_theme.dart';
import '../widgets/music_artwork.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.controller, this.favorites});

  final Favorites? favorites;
  final PlaybackController controller;

  String _time(Duration value) =>
      '${value.inMinutes}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Now Playing'),
          actions: [
            if (favorites != null && controller.currentSong != null)
              FavoriteButton(
                favorites: favorites!,
                song: controller.currentSong!,
              ),
          ],
        ),
        body: controller.currentSong == null
            ? const Center(child: Text('Nothing playing'))
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Center(
                          child: MusicArtwork(size: 220, active: true),
                        ),
                      ),
                      Text(
                        controller.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        controller.artist,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      StreamBuilder<Duration>(
                        stream: controller.player.positionStream,
                        builder: (context, snapshot) {
                          final duration =
                              controller.player.duration ?? Duration.zero;
                          final position = snapshot.data ?? Duration.zero;
                          final max = duration.inMilliseconds;
                          return Column(
                            children: [
                              Slider(
                                value: position.inMilliseconds
                                    .clamp(0, max)
                                    .toDouble(),
                                max: max > 0 ? max.toDouble() : 1,
                                onChanged: max > 0
                                    ? (value) => controller.seek(
                                        Duration(milliseconds: value.round()),
                                      )
                                    : null,
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_time(position)),
                                  Text(_time(duration)),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: controller.previous,
                            tooltip: 'Previous',
                            icon: const Icon(Icons.skip_previous_rounded),
                            iconSize: 44,
                          ),
                          const SizedBox(width: 20),
                          StreamBuilder<bool>(
                            stream: controller.player.playingStream,
                            initialData: controller.player.playing,
                            builder: (context, snapshot) => IconButton.filled(
                              onPressed: controller.togglePlayback,
                              tooltip: snapshot.data == true ? 'Pause' : 'Play',
                              iconSize: 40,
                              icon: Icon(
                                snapshot.data == true
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            onPressed: controller.next,
                            tooltip: 'Next',
                            icon: const Icon(Icons.skip_next_rounded),
                            iconSize: 44,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed: controller.toggleShuffle,
                            tooltip: controller.mode == PlaybackMode.shuffle
                                ? 'Shuffle on'
                                : 'Shuffle off',
                            icon: const Icon(Icons.shuffle_rounded),
                            color: controller.mode == PlaybackMode.shuffle
                                ? context.palette.primary
                                : context.palette.secondaryText,
                          ),
                          IconButton(
                            onPressed: controller.cycleRepeat,
                            tooltip: switch (controller.mode) {
                              PlaybackMode.repeatAll => 'Repeat all',
                              PlaybackMode.repeatOne => 'Repeat one',
                              _ => 'Repeat off',
                            },
                            icon: Icon(
                              controller.mode == PlaybackMode.repeatOne
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                            ),
                            color:
                                controller.mode == PlaybackMode.repeatAll ||
                                    controller.mode == PlaybackMode.repeatOne
                                ? context.palette.primary
                                : context.palette.secondaryText,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
