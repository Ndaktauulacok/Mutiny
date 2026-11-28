import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/models/models.dart';
import 'package:mutiny/services/player_controller.dart';

Track t(int i) => Track(id: '$i', title: 'Song $i', artist: 'A', uri: 'https://x/$i', source: TrackSource.audius);

void main() {
  final list = [for (var i = 0; i < 20; i++) t(i)];
  List<int> ids(List<Track> l) => [for (final x in l) int.parse(x.id)];

  group('Play', () {
    test('shuffle off keeps the list order', () {
      expect(ids(PlayerController.shuffleOrder(list, shuffle: false)), List.generate(20, (i) => i));
    });

    test('shuffle on: tapped song first, every song exactly once, order mixed', () {
      final o = PlayerController.shuffleOrder(list, first: 7, shuffle: true, random: math.Random(1));
      expect(o.first.id, '7');
      expect(ids(o)..sort(), List.generate(20, (i) => i));
      expect(ids(o), isNot(List.generate(20, (i) => i)));
    });

    test('shuffle on with Play: random first song, still every song once', () {
      final o = PlayerController.shuffleOrder(list, shuffle: true, random: math.Random(3));
      expect(ids(o).toSet().length, 20);
    });
  });

  group('switching while a song plays', () {
    test('turning shuffle ON mid-song: the rest is random, current keeps playing', () {
      // Playing song 5 of the list in order.
      final r = PlayerController.reorderAround(list, 5, list, shuffle: true, random: math.Random(2));
      expect(r.before, isEmpty);
      expect(r.after.length, 19);
      expect(r.after.map((x) => x.id), isNot(contains('5')));
      // The next songs are not simply 6, 7, 8…
      expect(ids(r.after).take(5).toList(), isNot([6, 7, 8, 9, 10]));
    });

    test('turning shuffle OFF mid-song: next songs follow the list after the current one', () {
      final shuffled = PlayerController.shuffleOrder(list, first: 12, shuffle: true, random: math.Random(4));
      // Some songs later, song at queue position 3 is playing.
      final cur = int.parse(shuffled[3].id);
      final r = PlayerController.reorderAround(shuffled, 3, list, shuffle: false);
      expect(ids(r.before), List.generate(cur, (i) => i));
      expect(ids(r.after), List.generate(19 - cur, (i) => cur + 1 + i));
    });

    test('off keeps songs added to the queue later', () {
      final extra = t(99);
      final queue = [...list.reversed, extra];
      final r = PlayerController.reorderAround(queue, 0, list, shuffle: false); // song 19 playing
      expect(ids(r.before), List.generate(19, (i) => i));
      expect(ids(r.after), [99]);
    });

    test('on → off → on never loses or duplicates a song', () {
      var queue = List.of(list);
      var cur = 4;
      for (final on in [true, false, true, false]) {
        final r = PlayerController.reorderAround(queue, cur, list, shuffle: on, random: math.Random(cur));
        final playing = queue[cur];
        queue = [...r.before, playing, ...r.after];
        cur = r.before.length;
        expect(ids(queue)..sort(), List.generate(20, (i) => i));
        expect(queue[cur], playing);
      }
    });
  });
}
