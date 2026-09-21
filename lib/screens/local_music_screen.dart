import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../playback/playback_controller.dart';
import '../theme/melodify_theme.dart';
import '../widgets/music_artwork.dart';
import '../models/local_music_folder.dart';
import '../widgets/local_song_list.dart';
import 'local_music_folder_screen.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key, required this.controller});

  final PlaybackController controller;

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  List<SongModel> _songs = [];
  List<LocalMusicFolder> _folders = [];
  bool _showFolders = false;
  int _songsWithoutFolder = 0;
  bool _isLoading = true;
  bool _permissionDenied = false;
  bool _permissionUnavailable = false;
  int? _loadingSongId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _playSong(SongModel song, List<SongModel> queue) async {
    setState(() {
      _loadingSongId = song.id;
    });

    try {
      await widget.controller.selectSong(queue, song);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load "${song.title}": $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingSongId = null;
        });
      }
    }
  }

  Future<void> _loadSongs({bool isRetry = false}) async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
      _permissionUnavailable = false;
      _errorMessage = null;
    });

    try {
      var hasPermission = await _audioQuery.permissionsStatus();

      if (!hasPermission) {
        hasPermission = await _audioQuery.permissionsRequest();
      }

      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _permissionDenied = !isRetry;
            _permissionUnavailable = isRetry;
          });
        }
        return;
      }

      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      final folders = LocalMusicFolder.groupSongs(songs);

      if (mounted) {
        setState(() {
          _songs = songs;
          _folders = folders;
          _songsWithoutFolder =
              songs.length -
              folders.fold<int>(
                0,
                (count, folder) => count + folder.songs.length,
              );
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Local music could not be loaded. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Music')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _viewChip('Songs', false),
                  _viewChip('Folders', true),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _viewChip(String label, bool folders) {
    final selected = _showFolders == folders;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: context.palette.primary,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? context.palette.background : context.palette.text,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => setState(() => _showFolders = folders),
    );
  }

  Widget _buildFolders() {
    if (_folders.isEmpty) {
      return const _MessageView(
        message:
            'Folder paths are unavailable for these songs. '
            'You can still play all of them in Songs.',
        icon: Icons.folder_outlined,
      );
    }
    return ListView.separated(
      key: const PageStorageKey<String>('local-folders'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _folders.length + (_songsWithoutFolder > 0 ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _folders.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$_songsWithoutFolder '
              '${_songsWithoutFolder == 1 ? 'song has' : 'songs have'} '
              'no folder path. Find '
              '${_songsWithoutFolder == 1 ? 'it' : 'them'} in Songs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final folder = _folders[index];
        final count = folder.songs.length;
        return Card(
          child: ListTile(
            leading: const MusicArtwork(
              icon: Icons.folder_rounded,
              active: true,
            ),
            title: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count ${count == 1 ? 'song' : 'songs'}'),
                Text(
                  folder.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _loadingSongId != null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LocalMusicFolderScreen(
                          folder: folder,
                          audioPlayer: widget.controller.player,
                          onPlaySong: (song) => _playSong(song, folder.songs),
                        ),
                      ),
                    );
                  },
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionDenied) {
      return _MessageView(
        message: 'Allow audio access to discover music stored on this device.',
        onRetry: () => _loadSongs(isRetry: true),
      );
    }

    if (_permissionUnavailable) {
      return _MessageView(
        message:
            'Audio access is still denied. Allow Music and audio access '
            'for Melodify in Android Settings, then try again.',
        onRetry: () => _loadSongs(isRetry: true),
      );
    }

    if (_errorMessage != null) {
      return _MessageView(
        message: _errorMessage!,
        onRetry: () => _loadSongs(isRetry: true),
      );
    }

    if (_songs.isEmpty) {
      return const _MessageView(
        message: 'No local songs were found on this device.',
        icon: Icons.library_music_outlined,
      );
    }

    if (_showFolders) return _buildFolders();
    return LocalSongList(
      songs: _songs,
      audioPlayer: widget.controller.player,
      loadingSongId: _loadingSongId,
      onPlaySong: (song) => _playSong(song, _songs),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    this.onRetry,
    this.icon = Icons.music_note_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusicArtwork(size: 72, icon: icon, active: true),
              const SizedBox(height: 24),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: context.palette.secondaryText),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try Again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
