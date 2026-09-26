import '../library/playlists.dart';
import 'playlist_dialogs.dart';
import '../library/favorites.dart';
import 'favorite_button.dart';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../theme/melodify_theme.dart';
import 'music_artwork.dart';

/// Presentation only: the owner supplies the existing player and play callback.
class LocalSongList extends StatelessWidget {
  const LocalSongList({
    super.key,
    this.favorites,
    this.playlists,
    this.onRemoveFromPlaylist,
    required this.songs,
    required this.audioPlayer,
    required this.loadingSongId,
    required this.onPlaySong,
    this.storageKey = 'local-songs',
    this.showAlbum = false,
  });

  final Playlists? playlists;
  final Future<void> Function(SongModel)? onRemoveFromPlaylist;
  final Favorites? favorites;
  final List<SongModel> songs;
  final AudioPlayer audioPlayer;
  final int? loadingSongId;
  final Future<void> Function(SongModel) onPlaySong;
  final String storageKey;
  final bool showAlbum;

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours == 0) return '${duration.inMinutes}:$seconds';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours}:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: audioPlayer.playerStateStream,
      initialData: audioPlayer.playerState,
      builder: (context, snapshot) {
        final source = audioPlayer.audioSource;
        final sourceUri = source is UriAudioSource ? source.uri : null;
        final isPlaying = snapshot.data?.playing ?? false;

        return ListView.separated(
          key: PageStorageKey<String>(storageKey),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: songs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final song = songs[index];
            final artist = song.artist?.trim();
            final album = song.album?.trim();
            final artistLabel =
                artist == null ||
                    artist.isEmpty ||
                    artist.toLowerCase() == '<unknown>'
                ? 'Local Music'
                : artist;
            final subtitle =
                showAlbum &&
                    album != null &&
                    album.isNotEmpty &&
                    album.toLowerCase() != '<unknown>'
                ? '$artistLabel / $album'
                : artistLabel;
            // Read the existing source; selection never changes player state.
            final isCurrent =
                sourceUri != null &&
                ((song.data.trim().isNotEmpty &&
                        sourceUri == Uri.file(song.data)) ||
                    sourceUri.toString() == song.uri);

            return Semantics(
              selected: isCurrent,
              child: Material(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  selected: isCurrent,
                  leading: MusicArtwork(
                    active: isCurrent,
                    icon: isCurrent && isPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.music_note_rounded,
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (playlists != null || onRemoveFromPlaylist != null)
                        PopupMenuButton<String>(
                          tooltip: 'Actions for ${song.title}',
                          onSelected: (value) {
                            if (value == 'add') {
                              addSongToPlaylist(context, playlists!, song);
                            } else {
                              onRemoveFromPlaylist?.call(song);
                            }
                          },
                          itemBuilder: (_) => [
                            if (playlists != null)
                              const PopupMenuItem(
                                value: 'add',
                                child: Text('Add to playlist'),
                              ),
                            if (onRemoveFromPlaylist != null)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from playlist'),
                              ),
                          ],
                        ),
                      if (favorites != null)
                        FavoriteButton(favorites: favorites!, song: song),
                      if (playlists == null &&
                          song.duration != null &&
                          song.duration! >= 0)
                        Text(
                          _formatDuration(song.duration!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (loadingSongId == song.id || isCurrent)
                        const SizedBox(width: 8),
                      if (loadingSongId == song.id)
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (isCurrent)
                        Icon(
                          isPlaying
                              ? Icons.volume_up_rounded
                              : Icons.pause_rounded,
                          color: context.palette.highlight,
                          semanticLabel: isPlaying ? 'Playing' : 'Paused',
                        ),
                    ],
                  ),
                  onTap: loadingSongId == null ? () => onPlaySong(song) : null,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
