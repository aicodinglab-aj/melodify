import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/models/local_music_folder.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

SongModel song(int id, String path, String title) =>
    SongModel({'_id': id, '_data': path, 'title': title});

void main() {
  test(
    'groups by full parent path, keeping duplicate folder names separate',
    () {
      final songs = [
        song(1, '/storage/emulated/0/Music/English/b.mp3', 'Beta'),
        song(2, '/storage/emulated/0/Music/English/a.mp3', 'alpha'),
        song(3, '/storage/ABCD-1234/English/c.mp3', 'Other storage'),
        song(4, '/storage/emulated/0/Music/malayalam/d.mp3', 'Another song'),
      ];
      final folders = LocalMusicFolder.groupSongs(songs);
      expect(folders.map((f) => f.name), ['English', 'English', 'malayalam']);
      expect(folders.map((f) => f.path).toSet().length, 3);
      final internal = folders.singleWhere(
        (f) => f.path == '/storage/emulated/0/Music/English',
      );
      expect(internal.songs.map((s) => s.id), [2, 1]);
      expect(songs.map((s) => s.id), [1, 2, 3, 4]);
      expect(identical(internal.songs.last, songs.first), isTrue);
    },
  );

  test('uses direct parent folders without combining nested folders', () {
    final folders = LocalMusicFolder.groupSongs([
      song(1, '/Music/a.mp3', 'A'),
      song(2, '/Music/English/b.mp3', 'B'),
      song(3, '/Music/English/Live/c.mp3', 'C'),
    ]);
    expect(folders.map((f) => f.path).toSet(), {
      '/Music',
      '/Music/English',
      '/Music/English/Live',
    });
    expect(folders.every((f) => f.songs.length == 1), isTrue);
  });

  test('normalizes POSIX paths independently of the host platform', () {
    expect(
      LocalMusicFolder.parentPath('/Music//English/./live/../a.mp3'),
      '/Music/English',
    );
    expect(LocalMusicFolder.parentPath('/song.mp3'), '/');
    expect(LocalMusicFolder.parentPath('/Music/മലയാളം/a.mp3'), '/Music/മലയാളം');
    expect(
      LocalMusicFolder.parentPath('/Music/ My Music /a.mp3'),
      '/Music/ My Music ',
    );
    expect(
      LocalMusicFolder.parentPath('/Music/100% Hits/a.mp3'),
      '/Music/100% Hits',
    );
    expect(
      LocalMusicFolder.parentPath('file:///Music/My%20Music/a.mp3'),
      '/Music/My Music',
    );
  });

  test('unusable paths create no fictional folder and remain in the input', () {
    final invalidPaths = [
      '',
      '  ',
      'song.mp3',
      'Music/song.mp3',
      'content://media/audio/1',
      '/Music/',
      '/Music/.',
      '/Music/..',
      '/../song.mp3',
      'file://remote/Music/song.mp3',
      'file:///Music/%ZZ/song.mp3',
    ];
    for (final path in invalidPaths) {
      expect(LocalMusicFolder.parentPath(path), isNull, reason: path);
    }
    final songs = [
      song(1, '', 'Unknown folder'),
      song(2, 'content://media/audio/2', 'Content URI'),
      song(3, '/Music/known.mp3', 'Known'),
    ];
    expect(LocalMusicFolder.groupSongs(songs).single.songs.single.id, 3);
    expect(songs.length, 3);
    expect(LocalMusicFolder.groupSongs([]), isEmpty);
  });

  test('preserves case-sensitive folder identity and immutable membership', () {
    final folders = LocalMusicFolder.groupSongs([
      song(1, '/Music/Rock/a.mp3', 'A'),
      song(2, '/Music/rock/b.mp3', 'B'),
    ]);
    expect(folders.length, 2);
    expect(() => folders.first.songs.clear(), throwsUnsupportedError);
    expect(() => folders.clear(), throwsUnsupportedError);
  });
}
