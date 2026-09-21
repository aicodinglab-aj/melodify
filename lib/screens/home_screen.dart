import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/local_music_library.dart';
import '../library/playback_history.dart';
import '../playback/playback_controller.dart';
import '../widgets/music_artwork.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.library,
    required this.history,
    required this.onOpenLocalMusic,
  });

  final PlaybackController controller;
  final LocalMusicLibrary library;
  final PlaybackHistory history;
  final ValueChanged<bool> onOpenLocalMusic;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _loadingSongId;
  late final _changes = Listenable.merge([
    widget.library,
    widget.history,
    widget.controller,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.history.restore();
      widget.library.load();
    });
  }

  Future<void> _play(SongModel song, List<SongModel> displayed) async {
    if (_loadingSongId != null) return;
    setState(() => _loadingSongId = song.id);
    try {
      await widget.controller.selectSong(List.of(displayed), song);
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

  Widget _section(
    String title,
    String key,
    List<SongModel> songs,
    String empty,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (songs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(empty),
          )
        else
          SizedBox(
            height: 164 + MediaQuery.textScalerOf(context).scale(16) * 4,
            child: ListView.separated(
              key: PageStorageKey(key),
              scrollDirection: Axis.horizontal,
              itemCount: songs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final song = songs[index];
                final artist = song.artist?.trim();
                return SizedBox(
                  width: 176,
                  child: Card(
                    child: InkWell(
                      key: ValueKey('$key-${song.id}'),
                      onTap: _loadingSongId == null
                          ? () => _play(song, songs)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MusicArtwork(
                              size: 64,
                              active:
                                  widget.controller.currentSong?.id == song.id,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              artist == null ||
                                      artist.isEmpty ||
                                      artist.toLowerCase() == '<unknown>'
                                  ? 'Local Music'
                                  : artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const Spacer(),
                            if (_loadingSongId == song.id)
                              const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const Icon(Icons.play_circle_outline_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _libraryContent() {
    switch (widget.library.status) {
      case LibraryStatus.idle:
      case LibraryStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      case LibraryStatus.denied:
      case LibraryStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.library.status == LibraryStatus.denied
                  ? 'Allow Music and audio access for Melodify in Android Settings, then try again.'
                  : 'Local music could not be loaded. Please try again.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => widget.library.load(retry: true),
              child: const Text('Try Again'),
            ),
          ],
        );
      case LibraryStatus.ready:
        final played = widget.history.resolve(widget.library.songs);
        final added = recentlyAddedSongs(widget.library.songs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.library.songs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text('No local songs were found on this device.'),
              ),
            _section(
              'Recently Played',
              'recently-played',
              played,
              widget.history.restored
                  ? 'Play a local song to see it here. Unavailable songs are hidden.'
                  : 'Loading listening history...',
            ),
            _section(
              'Recently Added',
              'recently-added',
              added,
              'No songs with an available added date.',
            ),
            if (!widget.history.storageAvailable)
              const Text(
                'Listening history could not be saved or restored. New plays remain available for this session.',
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: _changes,
      builder: (context, _) => SingleChildScrollView(
        key: const PageStorageKey('home'),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Home',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                StreamBuilder<bool>(
                  stream: widget.controller.player.playingStream,
                  initialData: widget.controller.player.playing,
                  builder: (context, snapshot) => IconButton.filled(
                    onPressed: widget.controller.currentSong == null
                        ? null
                        : widget.controller.togglePlayback,
                    tooltip: snapshot.data == true ? 'Pause' : 'Play',
                    icon: Icon(
                      snapshot.data == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your music, close at hand.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Text('Quick Access', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.library_music_outlined),
                  label: const Text('Local Music'),
                  onPressed: () => widget.onOpenLocalMusic(false),
                ),
                ActionChip(
                  avatar: const Icon(Icons.music_note_rounded),
                  label: const Text('Songs'),
                  onPressed: () => widget.onOpenLocalMusic(false),
                ),
                ActionChip(
                  avatar: const Icon(Icons.folder_outlined),
                  label: const Text('Folders'),
                  onPressed: () => widget.onOpenLocalMusic(true),
                ),
              ],
            ),
            const SizedBox(height: 28),
            if (widget.controller.playbackError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.controller.playbackError!),
              ),
            _libraryContent(),
          ],
        ),
      ),
    ),
  );
}
