import 'dart:math';

import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/favorites.dart';
import '../library/local_music_library.dart';
import '../library/playlists.dart';
import '../playback/playback_controller.dart';
import '../playback/playback_queue.dart';
import '../widgets/local_song_list.dart';
import '../widgets/playlist_dialogs.dart';
import '../widgets/playlist_library_state.dart';
import 'playlist_add_songs_screen.dart';

class PlaylistDetailsScreen extends StatefulWidget {
  const PlaylistDetailsScreen({
    super.key,
    required this.playlistId,
    required this.playlists,
    required this.library,
    required this.controller,
    this.favorites,
  });
  final String playlistId;
  final Playlists playlists;
  final LocalMusicLibrary library;
  final PlaybackController controller;
  final Favorites? favorites;
  @override
  State<PlaylistDetailsScreen> createState() => _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends State<PlaylistDetailsScreen> {
  int? _loadingSongId;
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

  Future<void> _play(
    List<SongModel> songs,
    SongModel song, {
    bool? shuffle,
  }) async {
    if (_loadingSongId != null || songs.isEmpty) return;
    setState(() => _loadingSongId = song.id);
    // Explicit Play chooses sequential; row taps preserve the current mode.
    if (shuffle == true && widget.controller.mode != PlaybackMode.shuffle) {
      widget.controller.toggleShuffle();
    } else if (shuffle == false) {
      if (widget.controller.mode == PlaybackMode.shuffle) {
        widget.controller.toggleShuffle();
      }
      while (widget.controller.mode != PlaybackMode.sequential) {
        widget.controller.cycleRepeat();
      }
    }
    try {
      await widget.controller.selectSong(songs, song);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This song could not be played. It may no longer be available.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSongId = null);
    }
  }

  Future<void> _remove(SongModel song) async {
    try {
      await widget.playlists.removeSong(widget.playlistId, song);
      if (mounted) {
        playlistNotice(context, widget.playlists, 'Removed from playlist.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this playlist.')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: const Text(
          'This will remove the playlist, but your music files will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.playlists.delete(widget.playlistId);
      if (mounted) {
        playlistNotice(context, widget.playlists, 'Playlist deleted.');
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this playlist.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final playlist = widget.playlists.byId(widget.playlistId);
      final songs = widget.library.status == LibraryStatus.ready
          ? widget.playlists.resolve(widget.playlistId, widget.library.songs)
          : <SongModel>[];
      return Scaffold(
        appBar: AppBar(
          title: Text(
            playlist?.name ?? 'Playlist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (playlist != null)
              PopupMenuButton<String>(
                tooltip: 'Playlist options',
                onSelected: (value) {
                  if (value == 'rename') {
                    editPlaylistName(
                      context,
                      widget.playlists,
                      playlist: playlist,
                    );
                  } else {
                    _delete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename playlist'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete playlist'),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: !widget.playlists.restored
              ? const Center(child: CircularProgressIndicator())
              : playlist == null
              ? const Center(child: Text('This playlist no longer exists.'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            widget.library.status == LibraryStatus.ready
                                ? '${songs.length} available ${songs.length == 1 ? 'song' : 'songs'}'
                                : 'Song availability pending',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    songs.isEmpty || _loadingSongId != null
                                    ? null
                                    : () => _play(
                                        songs,
                                        songs.first,
                                        shuffle: false,
                                      ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play'),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    songs.isEmpty || _loadingSongId != null
                                    ? null
                                    : () => _play(
                                        songs,
                                        songs[Random().nextInt(songs.length)],
                                        shuffle: true,
                                      ),
                                icon: const Icon(Icons.shuffle),
                                label: const Text('Shuffle'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PlaylistAddSongsScreen(
                                      playlists: widget.playlists,
                                      playlistId: widget.playlistId,
                                      library: widget.library,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.playlist_add),
                                label: const Text('Add Songs'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!widget.playlists.storageAvailable)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Changes could not be saved. They remain available for this session.',
                        ),
                      ),
                    Expanded(
                      child: PlaylistLibraryState(
                        library: widget.library,
                        child: songs.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    playlist.songKeys.isEmpty
                                        ? 'No songs yet. Add some music to this playlist.'
                                        : 'Songs in this playlist are currently unavailable. Their saved entries are kept.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : LocalSongList(
                                songs: songs,
                                audioPlayer: widget.controller.player,
                                loadingSongId: _loadingSongId,
                                onPlaySong: (song) => _play(songs, song),
                                favorites: widget.favorites,
                                playlists: widget.playlists,
                                onRemoveFromPlaylist: _remove,
                                storageKey: 'playlist-${widget.playlistId}',
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      );
    },
  );
}
