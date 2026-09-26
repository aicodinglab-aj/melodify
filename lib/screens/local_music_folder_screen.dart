import '../library/playlists.dart';
import '../library/favorites.dart';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../models/local_music_folder.dart';
import '../widgets/local_song_list.dart';

class LocalMusicFolderScreen extends StatefulWidget {
  const LocalMusicFolderScreen({
    super.key,
    this.playlists,
    this.favorites,
    required this.folder,
    required this.audioPlayer,
    required this.onPlaySong,
  });

  final Playlists? playlists;
  final Favorites? favorites;
  final LocalMusicFolder folder;
  final AudioPlayer audioPlayer;
  final Future<void> Function(SongModel) onPlaySong;

  @override
  State<LocalMusicFolderScreen> createState() => _LocalMusicFolderScreenState();
}

class _LocalMusicFolderScreenState extends State<LocalMusicFolderScreen> {
  int? _loadingSongId;

  Future<void> _selectSong(SongModel song) async {
    if (_loadingSongId != null) return;
    setState(() => _loadingSongId = song.id);
    try {
      // Delegate to LocalMusicScreen's existing loading/fallback/playback logic.
      await widget.onPlaySong(song);
    } finally {
      if (mounted) setState(() => _loadingSongId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                widget.folder.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: LocalSongList(
                favorites: widget.favorites,
                playlists: widget.playlists,
                songs: widget.folder.songs,
                audioPlayer: widget.audioPlayer,
                loadingSongId: _loadingSongId,
                onPlaySong: _selectSong,
                storageKey: widget.folder.path,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
