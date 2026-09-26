import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:melodify/library/playlists.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_v1_test.dart' show song;

class MemoryPlaylistsStore implements PlaylistsStore {
  List<Playlist> data = [];
  bool failRead = false;
  bool failWrite = false;
  Completer<List<Playlist>>? readGate;
  Completer<void>? writeGate;
  int writes = 0;
  @override
  Future<List<Playlist>> read() async {
    if (failRead) throw StateError('read failure');
    return readGate == null ? List.of(data) : readGate!.future;
  }

  @override
  Future<void> write(List<Playlist> items) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw StateError('write failure');
    data = List.of(items);
  }
}

void main() {
  late MemoryPlaylistsStore store;
  late Playlists playlists;
  setUp(() {
    store = MemoryPlaylistsStore();
    playlists = Playlists(store: store);
  });
  tearDown(() => playlists.dispose());

  test(
    'create trims name, generates stable unique IDs and newest creation order',
    () async {
      final a = await playlists.create('  Evening  ');
      final b = await playlists.create('Morning');
      expect(a.name, 'Evening');
      expect(a.id, isNot(b.id));
      expect(a.createdAt.isUtc, isTrue);
      expect(playlists.items.map((p) => p.id), [b.id, a.id]);
      expect(store.data.map((p) => p.id), [b.id, a.id]);
      expect(() => playlists.items.clear(), throwsUnsupportedError);
      expect(() => a.songKeys.add('x'), throwsUnsupportedError);
    },
  );

  test(
    'reject empty, whitespace, overlong and case-insensitive duplicate names',
    () async {
      for (final name in ['', '  ', 'x' * 81]) {
        await expectLater(playlists.create(name), throwsFormatException);
      }
      await playlists.create('Mix');
      await expectLater(playlists.create('  MIX  '), throwsFormatException);
      expect(playlists.items.length, 1);
      await playlists.create('x' * 80);
    },
  );

  test('rename preserves ID, timestamp, songs and creation order', () async {
    final a = await playlists.create('First');
    await playlists.addSongs(a.id, [song(2), song(1)]);
    final b = await playlists.create('Second');
    await playlists.rename(a.id, '  Renamed  ');
    final renamed = playlists.byId(a.id)!;
    expect(renamed.name, 'Renamed');
    expect(renamed.createdAt, a.createdAt);
    expect(renamed.songKeys, ['path:/Music/2.mp3', 'path:/Music/1.mp3']);
    expect(playlists.items.map((p) => p.id), [b.id, a.id]);
    await expectLater(playlists.rename(a.id, 'SECOND'), throwsFormatException);
    await expectLater(playlists.rename(a.id, ' '), throwsFormatException);
    await playlists.rename(a.id, 'RENAMED');
  });

  test('add one/multiple songs appends in order, skips duplicates', () async {
    final p = await playlists.create('Mix');
    expect(await playlists.addSongs(p.id, [song(2)]), 1);
    expect(
      await playlists.addSongs(p.id, [song(1), song(2), song(3), song(1)]),
      2,
    );
    expect(await playlists.addSongs(p.id, [song(2)]), 0);
    expect(
      playlists.resolve(p.id, [song(1), song(2), song(3)]).map((s) => s.id),
      [2, 1, 3],
    );
  });

  test('remove and delete affect only the chosen playlist', () async {
    final a = await playlists.create('A');
    final b = await playlists.create('B');
    await playlists.addSongs(a.id, [song(1), song(2)]);
    await playlists.addSongs(b.id, [song(1)]);
    await playlists.removeSong(a.id, song(1));
    expect(playlists.resolve(a.id, [song(1), song(2)]).map((s) => s.id), [2]);
    expect(playlists.byId(b.id)!.songKeys, ['path:/Music/1.mp3']);
    await playlists.delete(a.id);
    expect(playlists.byId(a.id), isNull);
    expect(playlists.items.single.id, b.id);
    expect(store.data.single.id, b.id);
    await expectLater(playlists.addSongs(a.id, [song(1)]), throwsStateError);
  });

  test(
    'SharedPreferences restores metadata, song order, rename and deletion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = Playlists();
      final second = Playlists();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final a = await first.create('A');
      final b = await first.create('B');
      await first.addSongs(a.id, [song(2), song(1), song(3)]);
      await first.removeSong(a.id, song(1));
      await first.rename(a.id, 'New A');
      await first.delete(b.id);
      await second.restore();
      expect(second.items.single.toJson(), first.items.single.toJson());
      expect(second.items.single.songKeys, [
        'path:/Music/2.mp3',
        'path:/Music/3.mp3',
      ]);
      final prefs = await SharedPreferences.getInstance();
      final json = jsonDecode(
        prefs.getString(PreferencesPlaylistsStore.preferenceKey)!,
      );
      expect(json['version'], 1);
      expect((json['playlists'] as List).single['name'], 'New A');
    },
  );

  test(
    'missing identifiers are retained and return at their original position',
    () async {
      final p = await playlists.create('Mix');
      await playlists.addSongs(p.id, [song(99), song(2), song(1)]);
      expect(playlists.resolve(p.id, [song(1), song(2)]).map((s) => s.id), [
        2,
        1,
      ]);
      expect(playlists.byId(p.id)!.songKeys.length, 3);
      expect(playlists.resolve(p.id, []).isEmpty, isTrue);
      expect(
        playlists.resolve(p.id, [song(1), song(2), song(99)]).map((s) => s.id),
        [99, 2, 1],
      );
    },
  );

  test(
    'mutations wait for restoration and writes serialize snapshots',
    () async {
      final original = Playlist(
        id: 'existing',
        name: 'Existing',
        createdAt: DateTime.utc(2026),
        songKeys: [],
      );
      store.readGate = Completer<List<Playlist>>();
      store.writeGate = Completer<void>();
      final a = playlists.addSongs(original.id, [song(1)]);
      final b = playlists.addSongs(original.id, [song(2)]);
      store.readGate!.complete([original]);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1);
      expect(playlists.byId(original.id)!.songKeys.length, 2);
      store.writeGate!.complete();
      await Future.wait([a, b]);
      expect(store.writes, 2);
      expect(store.data.single.songKeys, [
        'path:/Music/1.mp3',
        'path:/Music/2.mp3',
      ]);
    },
  );

  test(
    'failed writes preserve session edits and recover on next change',
    () async {
      await playlists.restore();
      store.failWrite = true;
      final p = await playlists.create('Session');
      expect(playlists.storageAvailable, isFalse);
      expect(playlists.byId(p.id), isNotNull);
      store.failWrite = false;
      await playlists.addSongs(p.id, [song(1)]);
      expect(playlists.storageAvailable, isTrue);
      expect(store.data.single.songKeys.length, 1);
    },
  );

  test(
    'read failure blocks edits and retry restores without overwriting',
    () async {
      store.failRead = true;
      await playlists.restore();
      expect(playlists.loadFailed, isTrue);
      await expectLater(playlists.create('Bad'), throwsStateError);
      expect(store.writes, 0);
      store.failRead = false;
      await playlists.restore(retry: true);
      expect(playlists.loadFailed, isFalse);
      await playlists.create('Good');
    },
  );

  test('malformed or newer preference data is preserved', () async {
    for (final raw in ['not json', '{"version":2,"playlists":[]}']) {
      SharedPreferences.setMockInitialValues({
        PreferencesPlaylistsStore.preferenceKey: raw,
      });
      final repo = Playlists();
      await repo.restore();
      expect(repo.loadFailed, isTrue);
      await expectLater(repo.create('New'), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getString(
          PreferencesPlaylistsStore.preferenceKey,
        ),
        raw,
      );
      repo.dispose();
    }
  });
}
