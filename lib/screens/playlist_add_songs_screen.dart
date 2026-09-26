import 'package:flutter/material.dart';

import '../library/local_music_library.dart';
import '../library/playlists.dart';
import '../widgets/local_song_artwork.dart';
import '../widgets/playlist_dialogs.dart';
import '../widgets/playlist_library_state.dart';

class PlaylistAddSongsScreen extends StatefulWidget {
  const PlaylistAddSongsScreen({
    super.key,
    required this.playlists,
    required this.playlistId,
    required this.library,
  });
  final Playlists playlists;
  final String playlistId;
  final LocalMusicLibrary library;
  @override
  State<PlaylistAddSongsScreen> createState() => _PlaylistAddSongsScreenState();
}

class _PlaylistAddSongsScreenState extends State<PlaylistAddSongsScreen> {
  final _selected = <String>{};
  String _query = '';
  bool _saving = false;
  late final _changes = Listenable.merge([widget.library, widget.playlists]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.library.load();
    });
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      final available = {
        for (final song in widget.library.songs) Playlists.keyFor(song): song,
      };
      // Selection insertion order survives filtering and determines append order.
      final count = await widget.playlists.addSongs(
        widget.playlistId,
        _selected.where(available.containsKey).map((key) => available[key]!),
      );
      if (mounted) {
        playlistNotice(
          context,
          widget.playlists,
          'Added $count ${count == 1 ? 'song' : 'songs'}.',
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not add songs. The playlist may have been deleted.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final playlist = widget.playlists.byId(widget.playlistId);
      final songs = _query.trim().isEmpty
          ? widget.library.songs
          : searchLocalSongs(widget.library.songs, _query);
      return Scaffold(
        appBar: AppBar(title: const Text('Add Songs')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search songs, artists, albums',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: PlaylistLibraryState(
                  library: widget.library,
                  child: playlist == null
                      ? const Center(
                          child: Text('This playlist no longer exists.'),
                        )
                      : songs.isEmpty
                      ? Center(
                          child: Text(
                            _query.trim().isEmpty
                                ? 'No local songs were found on this device.'
                                : 'No songs found',
                          ),
                        )
                      : ListView.builder(
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final key = Playlists.keyFor(song);
                            final present = playlist.songKeys.contains(key);
                            final artist = song.artist?.trim();
                            final artistLabel =
                                artist == null ||
                                    artist.isEmpty ||
                                    artist.toLowerCase() == '<unknown>'
                                ? 'Local Music'
                                : artist;
                            return CheckboxListTile(
                              secondary: LocalSongArtwork(song: song),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                present
                                    ? '$artistLabel / Already in playlist'
                                    : artistLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: present || _selected.contains(key),
                              onChanged: present || _saving
                                  ? null
                                  : (value) => setState(() {
                                      if (value == true) {
                                        _selected.add(key);
                                      } else {
                                        _selected.remove(key);
                                      }
                                    }),
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed:
                      _saving ||
                          _selected.isEmpty ||
                          playlist == null ||
                          widget.library.status != LibraryStatus.ready
                      ? null
                      : _add,
                  icon: const Icon(Icons.playlist_add),
                  label: Text('Add ${_selected.length} songs'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
