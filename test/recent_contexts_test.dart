import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/models/models.dart';
import 'package:mutiny/services/library_store.dart';
import 'package:mutiny/services/sync_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlayContext ctx(PlayContextType t, String id, [String? title]) => PlayContext(type: t, id: id, title: title ?? id);

void main() {
  test('play contexts survive JSON and unknown types are dropped', () {
    final c = PlayContext(
      type: PlayContextType.remote,
      id: 'abc',
      title: 'Chill Ambient',
      subtitle: 'Playlist',
      artworkUrl: 'https://x/y.jpg',
      data: {'id': 'abc', 'title': 'Chill Ambient'},
    );
    final back = PlayContext.fromJson(c.toJson())!;
    expect(back, c);
    expect(back.title, 'Chill Ambient');
    expect(back.data['id'], 'abc');
    expect(PlayContext.fromJson({'type': 'podcast', 'cid': 'x'}), isNull);
  });

  test('newest first, no duplicates, capped, saved and removable', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = LibraryStore();
    await lib.load();
    lib.markPlayedFrom(ctx(PlayContextType.liked, 'liked', 'Liked Songs'));
    lib.markPlayedFrom(ctx(PlayContextType.artist, 'a1', 'Tame Impala'));
    lib.markPlayedFrom(ctx(PlayContextType.liked, 'liked', 'Liked Songs'));
    expect(lib.recentContexts.map((c) => c.title), ['Liked Songs', 'Tame Impala']);

    for (var i = 0; i < 30; i++) {
      lib.markPlayedFrom(ctx(PlayContextType.genre, 'g$i'));
    }
    expect(lib.recentContexts.length, LibraryStore.maxContexts);
    expect(lib.recentContexts.first.id, 'g29');

    final again = LibraryStore();
    await again.load();
    expect(again.recentContexts.length, LibraryStore.maxContexts);
    again.removeRecentContext(again.recentContexts.first);
    expect(again.recentContexts.first.id, 'g28');
  });

  test('deleting a playlist removes it from recents', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = LibraryStore();
    await lib.load();
    final p = lib.createPlaylist('Good Time');
    lib.markPlayedFrom(ctx(PlayContextType.playlist, p.id, p.name));
    expect(lib.recentContexts, hasLength(1));
    lib.deletePlaylist(p);
    expect(lib.recentContexts, isEmpty);
  });

  test('recents sync between devices', () async {
    SharedPreferences.setMockInitialValues({});
    final phone = LibraryStore();
    await phone.load();
    phone.markPlayedFrom(ctx(PlayContextType.artist, 'a1', 'Tame Impala'));
    phone.markPlayedFrom(ctx(PlayContextType.liked, 'liked', 'Liked Songs'));
    final snap = phone.syncSnapshot();
    expect(snap.containsKey('context/all'), isTrue);
    expect(SyncMerge.listKinds, contains('context'));

    SharedPreferences.setMockInitialValues({});
    final laptop = LibraryStore();
    await laptop.load();
    laptop.applySynced('context/all', snap['context/all']);
    expect(laptop.recentContexts.map((c) => c.title), ['Liked Songs', 'Tame Impala']);

    // Both devices played something different while apart: nothing is lost.
    final merged = SyncMerge.unionLists(
      {'items': [ctx(PlayContextType.genre, 'Lo-Fi').toJson()]},
      snap['context/all']!,
    );
    laptop.applySynced('context/all', merged);
    expect(laptop.recentContexts.map((c) => c.id).toSet(), {'Lo-Fi', 'a1', 'liked'});
  });
}
