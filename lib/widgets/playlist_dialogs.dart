import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/playlists.dart';

void playlistNotice(BuildContext context, Playlists playlists, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        playlists.storageAvailable
            ? message
            : '$message Changes could not be saved and are available for this session only.',
      ),
    ),
  );
}

Future<String?> editPlaylistName(
  BuildContext context,
  Playlists playlists, {
  Playlist? playlist,
}) async {
  final id = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(playlists: playlists, playlist: playlist),
  );
  if (id != null && context.mounted) {
    playlistNotice(
      context,
      playlists,
      playlist == null ? 'Playlist created.' : 'Playlist renamed.',
    );
  }
  return id;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.playlists, this.playlist});
  final Playlists playlists;
  final Playlist? playlist;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.playlist?.name);
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.playlist;
      String id;
      if (existing == null) {
        id = (await widget.playlists.create(_name.text)).id;
      } else {
        await widget.playlists.rename(existing.id, _name.text);
        id = existing.id;
      }
      if (mounted) Navigator.of(context).pop(id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException ? error.message : 'Playlist could not be updated. Restore playlists and try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.playlist == null ? 'Create Playlist' : 'Rename playlist',
    ),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: Playlists.maxNameLength,
      textCapitalization: TextCapitalization.sentences,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: 'Playlist name',
        errorText: _error,
        errorMaxLines: 3,
      ),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(widget.playlist == null ? 'Create' : 'Save'),
      ),
    ],
  );
}

Future<void> addSongToPlaylist(
  BuildContext context,
  Playlists playlists,
  SongModel song,
) async {
  await playlists.restore();
  if (!context.mounted) return;
  final id = await showDialog<String>(
    context: context,
    builder: (_) => _PlaylistPicker(playlists: playlists),
  );
  if (id == null || !context.mounted) return;
  try {
    final count = await playlists.addSongs(id, [song]);
    if (context.mounted) {
      playlistNotice(
        context,
        playlists,
        count == 0 ? 'Song is already in this playlist.' : 'Added to playlist.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add the song. Please try again.'),
        ),
      );
    }
  }
}

class _PlaylistPicker extends StatelessWidget {
  const _PlaylistPicker({required this.playlists});
  final Playlists playlists;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playlists,
    builder: (context, _) => AlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 360,
        height: 300,
        child: playlists.loadFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Playlists could not be restored. Your saved data has been kept.',
                  ),
                  TextButton(
                    onPressed: () => playlists.restore(retry: true),
                    child: const Text('Try Again'),
                  ),
                ],
              )
            : ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Create Playlist'),
                    onTap: () async {
                      final id = await editPlaylistName(context, playlists);
                      if (id != null && context.mounted) {
                        Navigator.of(context).pop(id);
                      }
                    },
                  ),
                  if (playlists.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No playlists yet. Create one to add this song.',
                      ),
                    ),
                  for (final playlist in playlists.items)
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(playlist.name),
                      onTap: () => Navigator.of(context).pop(playlist.id),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
