import 'package:flutter/material.dart';

import '../library/favorites.dart';
import '../library/local_music_library.dart';
import '../library/playlists.dart';
import '../playback/playback_controller.dart';
import '../widgets/music_artwork.dart';
import '../widgets/local_song_artwork.dart';
import '../widgets/playlist_dialogs.dart';
import 'playlist_details_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.playlists,
    required this.library,
    required this.controller,
    this.favorites,
  });
  final Playlists playlists;
  final LocalMusicLibrary library;
  final PlaybackController controller;
  final Favorites? favorites;
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  late final _changes = Listenable.merge([widget.playlists, widget.library]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.playlists.restore();
      widget.library.load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playlists')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _changes,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed:
                    !widget.playlists.restored || widget.playlists.loadFailed
                    ? null
                    : () => editPlaylistName(context, widget.playlists),
                icon: const Icon(Icons.add),
                label: const Text('Create Playlist'),
              ),
            ),
            if (!widget.playlists.storageAvailable)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      widget.playlists.loadFailed
                          ? 'Playlists could not be restored. Your saved data has been kept.'
                          : 'Changes could not be saved. Playlists remain available for this session.',
                    ),
                    if (widget.playlists.loadFailed)
                      TextButton(
                        onPressed: () => widget.playlists.restore(retry: true),
                        child: const Text('Try Again'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: !widget.playlists.restored
                  ? const Center(child: CircularProgressIndicator())
                  : widget.playlists.loadFailed
                  ? const SizedBox.shrink()
                  : widget.playlists.items.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MusicArtwork(
                              icon: Icons.queue_music_rounded,
                              size: 80,
                              active: true,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No playlists yet',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Create a playlist to organize your music.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: widget.playlists.items.length,
                      itemBuilder: (context, index) {
                        final playlist = widget.playlists.items[index];
                        final available = widget.playlists.resolve(
                          playlist.id,
                          widget.library.songs,
                        );
                        final count = available.length;
                        return ListTile(
                          leading: LocalSongArtwork(
                            songs: available,
                            icon: Icons.queue_music_rounded,
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            widget.library.status == LibraryStatus.ready
                                ? '$count available ${count == 1 ? 'song' : 'songs'}'
                                : 'Song availability pending',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PlaylistDetailsScreen(
                                playlistId: playlist.id,
                                playlists: widget.playlists,
                                library: widget.library,
                                controller: widget.controller,
                                favorites: widget.favorites,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
