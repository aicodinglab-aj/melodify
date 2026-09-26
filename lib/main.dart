import 'library/playlists.dart';
import 'library/favorites.dart';
import 'library/local_music_library.dart';
import 'library/playback_history.dart';
import 'screens/local_music_screen.dart';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'playback/playback_controller.dart';
import 'playback/playback_runtime.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/search_screen.dart';
import 'theme/melodify_theme.dart';
import 'theme/melodify_theme_controller.dart';
import 'widgets/music_artwork.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await PlaybackRuntime.initialize();
  runApp(MelodifyApp(runtime: runtime));
}

class MelodifyApp extends StatefulWidget {
  const MelodifyApp({super.key, required this.runtime});

  final PlaybackRuntime runtime;

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
        home: MainScreen(
          themeController: _themeController,
          runtime: widget.runtime,
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.themeController,
    required this.runtime,
  });

  final PlaybackRuntime runtime;

  final MelodifyThemeController themeController;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;
  AudioPlayer get _audioPlayer => _controller.player;
  PlaybackController get _controller => widget.runtime.controller;
  PlaybackHistory get _history => widget.runtime.history;
  Favorites get _favorites => widget.runtime.favorites;
  Playlists get _playlists => widget.runtime.playlists;
  LocalMusicLibrary get _library => widget.runtime.library;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.runtime.start();
    });
  }

  final _homeNavigatorKey = GlobalKey<NavigatorState>();
  final _libraryNavigatorKey = GlobalKey<NavigatorState>();

  late final List<Widget> pages = [
    Navigator(
      key: _homeNavigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => HomeScreen(
          controller: _controller,
          library: _library,
          history: _history,
          onOpenLocalMusic: _openLocalMusic,
        ),
      ),
    ),
    SearchScreen(
      playlists: _playlists,
      controller: _controller,
      library: _library,
      favorites: _favorites,
    ),
    Navigator(
      key: _libraryNavigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => LibraryScreen(
          playlists: _playlists,
          favorites: _favorites,
          library: _library,
          controller: _controller,
          themeController: widget.themeController,
        ),
      ),
    ),
  ];

  void _openLocalMusic(bool folders) {
    _homeNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMusicScreen(
          playlists: _playlists,
          favorites: _favorites,
          controller: _controller,
          library: _library,
          initialShowFolders: folders,
        ),
      ),
    );
  }

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
                  builder: (_) => NowPlayingScreen(
                    controller: _controller,
                    favorites: _favorites,
                  ),
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
                              _controller.seek(
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        body: IndexedStack(
          index: currentIndex,
          children: [
            NavigatorPopHandler<void>(
              enabled: currentIndex == 0,
              onPopWithResult: (_) {
                if (currentIndex == 0) _homeNavigatorKey.currentState!.pop();
              },
              child: pages[0],
            ),
            pages[1],
            NavigatorPopHandler<void>(
              enabled: currentIndex == 2,
              onPopWithResult: (_) {
                if (currentIndex == 2) _libraryNavigatorKey.currentState!.pop();
              },
              child: pages[2],
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: widget.runtime.backgroundIssue,
              builder: (context, issue, _) => issue == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(issue),
                    ),
            ),
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
