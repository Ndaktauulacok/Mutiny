import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/services/sync_merge.dart';

Map<String, dynamic> list(List<String> ids) => {
      'items': [for (final id in ids) {'id': id, 'source': 'audius', 'title': 'Song $id'}],
    };

void main() {
  test('hash ignores key order (Postgres jsonb reorders keys)', () {
    expect(SyncMerge.hash({'a': 1, 'b': [{'x': 1, 'y': 2}]}), SyncMerge.hash({'b': [{'y': 2, 'x': 1}], 'a': 1}));
    expect(SyncMerge.hash({'a': 1}), isNot(SyncMerge.hash({'a': 2})));
    expect(SyncMerge.hash({'d': 180.0}), SyncMerge.hash({'d': 180}));
  });

  test('new device signs in: takes the account data, keeps its own new playlist', () {
    final remote = {'liked/all': list(['1', '2']), 'profile/me': {'name': 'Amreel'}, 'playlist/p1': {'name': 'Gym'}};
    final local = {'liked/all': list([]), 'profile/me': {'name': 'Listener'}, 'playlist/p9': {'name': 'Tablet mix'}};
    final plan = SyncMerge.plan(local: local, remote: remote, synced: {}, firstSync: true);
    expect(plan.apply['liked/all'], list(['1', '2']));
    expect(plan.apply['profile/me'], {'name': 'Amreel'});
    expect(plan.apply['playlist/p1'], {'name': 'Gym'});
    expect(plan.push.keys, contains('playlist/p9'));
    expect(plan.push.containsKey('profile/me'), isFalse);
  });

  test('change on this device only is pushed; change in cloud only is applied', () {
    final base = {'name': 'Gym'};
    final synced = {'playlist/p1': SyncMerge.hash(base), 'playlist/p2': SyncMerge.hash(base)};
    final plan = SyncMerge.plan(
      local: {'playlist/p1': {'name': 'Gym 2'}, 'playlist/p2': base},
      remote: {'playlist/p1': base, 'playlist/p2': {'name': 'Renamed on phone'}},
      synced: synced,
    );
    expect(plan.push['playlist/p1'], {'name': 'Gym 2'});
    expect(plan.apply['playlist/p2'], {'name': 'Renamed on phone'});
  });

  test('deletes travel both ways', () {
    final p = {'name': 'Old'};
    final h = SyncMerge.hash(p);
    final plan = SyncMerge.plan(
      local: {'playlist/b': p}, // a: deleted here
      remote: {'playlist/a': p, 'playlist/b': null}, // b: deleted on another device
      synced: {'playlist/a': h, 'playlist/b': h},
    );
    expect(plan.push.containsKey('playlist/a'), isTrue);
    expect(plan.push['playlist/a'], isNull);
    expect(plan.apply.containsKey('playlist/b'), isTrue);
    expect(plan.apply['playlist/b'], isNull);
  });

  test('likes added on two devices offline are combined, not lost', () {
    final synced = {'liked/all': SyncMerge.hash(list(['1']))};
    final plan = SyncMerge.plan(
      local: {'liked/all': list(['2', '1'])},
      remote: {'liked/all': list(['3', '1'])},
      synced: synced,
    );
    final ids = (plan.apply['liked/all']!['items'] as List).map((e) => e['id']).toList();
    expect(ids, ['3', '1', '2']);
    expect(plan.push['liked/all'], plan.apply['liked/all']);
  });

  test('nothing to do when both sides match', () {
    final d = {'name': 'Same'};
    final plan = SyncMerge.plan(local: {'playlist/x': d}, remote: {'playlist/x': {...d}}, synced: {});
    expect(plan.apply, isEmpty);
    expect(plan.push, isEmpty);
  });
}
