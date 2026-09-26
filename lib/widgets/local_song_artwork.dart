import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/local_artwork_repository.dart';
import 'music_artwork.dart';

class LocalArtworkScope extends InheritedWidget {
  const LocalArtworkScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final LocalArtworkRepository repository;
  static LocalArtworkRepository of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LocalArtworkScope>()
          ?.repository ??
      LocalArtworkRepository.shared;
  @override
  bool updateShouldNotify(LocalArtworkScope oldWidget) =>
      repository != oldWidget.repository;
}

/// One artwork renderer for song rows, covers, current playback and Home.
class LocalSongArtwork extends StatefulWidget {
  const LocalSongArtwork({
    super.key,
    this.song,
    this.songs,
    this.size = 48,
    this.active = false,
    this.icon = Icons.music_note_rounded,
    this.large = false,
  });
  final SongModel? song;

  /// Playlist order; lazily stop at the first available artwork.
  final List<SongModel>? songs;
  final double size;
  final bool active;
  final IconData icon;
  final bool large;
  @override
  State<LocalSongArtwork> createState() => _LocalSongArtworkState();
}

class _LocalSongArtworkState extends State<LocalSongArtwork> {
  LocalArtworkRepository? _repository;
  String? _key;
  Future<Uint8List?>? _future;
  int _pixels = 128;
  int _generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(LocalSongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final repository = LocalArtworkScope.of(context);
    final requested = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    final pixels = LocalArtworkRepository.bucket(
      requested.clamp(1, widget.large ? 512 : 256),
    );
    final songs =
        widget.songs ?? (widget.song == null ? <SongModel>[] : [widget.song!]);
    final key = songs.isEmpty
        ? null
        : songs
              .map((song) => LocalArtworkRepository.key(song, pixels))
              .join('|');
    if (key == _key && repository == _repository) return;
    _repository = repository;
    _key = key;
    _pixels = pixels;
    final generation = ++_generation;
    _future = songs.isEmpty
        ? null
        : _loadFirst(songs, repository, pixels, generation);
  }

  Future<Uint8List?> _loadFirst(
    List<SongModel> songs,
    LocalArtworkRepository repository,
    int pixels,
    int generation,
  ) async {
    for (final song in songs) {
      if (!mounted || generation != _generation) return null;
      final bytes = await repository.load(song, pixels: pixels);
      if (bytes != null) return bytes;
    }
    return null;
  }

  Widget _fallback() =>
      MusicArtwork(size: widget.size, active: widget.active, icon: widget.icon);
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: FutureBuilder<Uint8List?>(
      key: ValueKey(_key),
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        if (bytes == null) return _fallback();
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.size > 64 ? 20 : 12),
          child: Image(
            image: ResizeImage(
              MemoryImage(bytes),
              width: _pixels,
              height: _pixels,
              policy: ResizeImagePolicy.fit,
            ),
            key: ValueKey(_key),
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: false,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => _fallback(),
          ),
        );
      },
    ),
  );
}
