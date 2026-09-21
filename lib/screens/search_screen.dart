import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/local_music_library.dart';
import '../playback/playback_controller.dart';
import '../widgets/local_song_list.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
    required this.library,
  });
  final PlaybackController controller;
  final LocalMusicLibrary library;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';
  int? _loadingSongId;

  Future<void> _play(SongModel song, List<SongModel> results) async {
    if (_loadingSongId != null) return;
    setState(() => _loadingSongId = song.id);
    try {
      // selectSong copies this result snapshot into the existing playback queue.
      await widget.controller.selectSong(results, song);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load "${song.title}": $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSongId = null);
    }
  }

  Widget _message(String text, {bool retry = false}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => widget.library.load(retry: true),
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _results() {
    switch (widget.library.status) {
      case LibraryStatus.idle:
      case LibraryStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LibraryStatus.denied:
        return _message(
          'Allow Music and audio access for Melodify in Android Settings, then try again.',
          retry: true,
        );
      case LibraryStatus.failed:
        return _message(
          'Local music could not be loaded. Please try again.',
          retry: true,
        );
      case LibraryStatus.ready:
        break;
    }
    if (widget.library.songs.isEmpty) {
      return _message('No local songs were found on this device.');
    }
    if (_query.trim().isEmpty) {
      return _message(
        'Search your local music by song title, artist, or album.',
      );
    }
    final results = searchLocalSongs(widget.library.songs, _query);
    if (results.isEmpty) return _message('No songs found');
    return LocalSongList(
      songs: results,
      audioPlayer: widget.controller.player,
      loadingSongId: _loadingSongId,
      onPlaySong: (song) => _play(song, results),
      showAlbum: true,
      storageKey: 'search-results',
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search songs, artists, albums',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.library,
            builder: (context, _) => _results(),
          ),
        ),
      ],
    ),
  );
}
