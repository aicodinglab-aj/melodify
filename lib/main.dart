import 'library/local_music_library.dart';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'playback/playback_controller.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/search_screen.dart';
import 'theme/melodify_theme.dart';
import 'theme/melodify_theme_controller.dart';
import 'widgets/music_artwork.dart';

void main() {
  runApp(const MelodifyApp());
}

class MelodifyApp extends StatefulWidget {
  const MelodifyApp({super.key});

  @override
  State<MelodifyApp> createState() => _MelodifyAppState();
}

class _MelodifyAppState extends State<MelodifyApp> {
  final MelodifyThemeController _themeController = MelodifyThemeController();

  @override
  void initState() {
    super.initState();
    _themeController.restore();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Melodify',
        theme: _themeController.theme,
        home: MainScreen(themeController: _themeController),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.themeController});

  final MelodifyThemeController themeController;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final PlaybackController _controller = PlaybackController(_audioPlayer);
  final _library = LocalMusicLibrary();
  final _libraryNavigatorKey = GlobalKey<NavigatorState>();

  late final List<Widget> pages = [
    HomeScreen(controller: _controller),
    SearchScreen(controller: _controller, library: _library),
    Navigator(
      key: _libraryNavigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => LibraryScreen(
          library: _library,
          controller: _controller,
          themeController: widget.themeController,
        ),
      ),
    ),
  ];

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildMiniPlayer() {
    return StreamBuilder<Duration?>(
      stream: _audioPlayer.durationStream,
      initialData: _audioPlayer.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data;

        return StreamBuilder<Duration>(
          stream: _audioPlayer.positionStream,
          initialData: _audioPlayer.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final durationInMilliseconds = duration?.inMilliseconds ?? 0;
            final sliderPosition = durationInMilliseconds > 0
                ? position.inMilliseconds.clamp(0, durationInMilliseconds)
                : 0;

            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NowPlayingScreen(controller: _controller),
                ),
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: context.palette.elevated,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const MusicArtwork(active: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _controller.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _controller.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StreamBuilder<bool>(
                          stream: _audioPlayer.playingStream,
                          initialData: _audioPlayer.playing,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data ?? false;
                            return IconButton.filled(
                              onPressed: _controller.togglePlayback,
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
                        IconButton(
                          onPressed: _controller.close,
                          tooltip: 'Close player',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Slider(
                      min: 0,
                      max: durationInMilliseconds > 0
                          ? durationInMilliseconds.toDouble()
                          : 1,
                      value: sliderPosition.toDouble(),
                      label: _formatDuration(position),
                      semanticFormatterCallback: (value) => _formatDuration(
                        Duration(milliseconds: value.round()),
                      ),
                      onChanged: durationInMilliseconds > 0
                          ? (value) {
                              _audioPlayer.seek(
                                Duration(milliseconds: value.round()),
                              );
                            }
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_formatDuration(position)} / '
                        '${duration == null ? '--:--' : _formatDuration(duration)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _library.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        body: NavigatorPopHandler<void>(
          enabled: currentIndex == 2,
          onPopWithResult: (_) => _libraryNavigatorKey.currentState!.pop(),
          child: IndexedStack(index: currentIndex, children: pages),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.currentSong != null) _buildMiniPlayer(),
            NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) {
                if (index == 1) _library.load();
                setState(() {
                  currentIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Library',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
