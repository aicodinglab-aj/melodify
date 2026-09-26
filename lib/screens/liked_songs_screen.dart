import '../library/playlists.dart';

import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/favorites.dart';
import '../library/local_music_library.dart';
import '../playback/playback_controller.dart';
import '../theme/melodify_theme.dart';
import '../widgets/local_song_list.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({
    super.key,
    this.playlists,
    required this.favorites,
    required this.library,
    required this.controller,
  });

  final Playlists? playlists;
  final Favorites favorites;
  final LocalMusicLibrary library;
  final PlaybackController controller;

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  int? _loadingSongId;
  late final _changes = Listenable.merge([widget.favorites, widget.library]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.favorites.restore();
      widget.library.load();
    });
  }

  Future<void> _play(SongModel song, List<SongModel> displayed) async {
    if (_loadingSongId != null) return;
    setState(() => _loadingSongId = song.id);
    try {
      await widget.controller.selectSong(displayed, song);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not play "${song.title}". The file may no longer be available.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSongId = null);
    }
  }

  Widget _content() {
    final status = widget.library.status;
    if (!widget.favorites.restored ||
        status == LibraryStatus.idle ||
        status == LibraryStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == LibraryStatus.denied || status == LibraryStatus.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status == LibraryStatus.denied
                    ? 'Allow Music and audio access for Melodify in Android Settings, then try again.'
                    : 'Local music could not be loaded. Please try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => widget.library.load(retry: true),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    final songs = widget.favorites.resolve(widget.library.songs);
    if (songs.isEmpty) {
      final hasMissing = widget.favorites.keys.isNotEmpty;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border_rounded,
                size: 64,
                color: context.palette.primary,
              ),
              const SizedBox(height: 20),
              Text(
                hasMissing
                    ? 'Your liked songs are unavailable'
                    : 'No liked songs yet',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                hasMissing
                    ? 'Your favorites are saved. Songs will appear when they are available in your local library again.'
                    : 'Tap the heart in Local Music, Search, or Now Playing to keep your favorites here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return LocalSongList(
      songs: songs,
      audioPlayer: widget.controller.player,
      favorites: widget.favorites,
      playlists: widget.playlists,
      loadingSongId: _loadingSongId,
      onPlaySong: (song) => _play(song, songs),
      storageKey: 'liked-songs',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Liked Songs')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _changes,
        builder: (context, _) => Column(
          children: [
            if (!widget.favorites.storageAvailable)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Favorites could not be saved or restored. Changes remain available for this session.',
                ),
              ),
            Expanded(child: _content()),
          ],
        ),
      ),
    ),
  );
}
