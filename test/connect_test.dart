import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/models/models.dart';
import 'package:mutiny/services/connect_service.dart';
import 'package:mutiny/services/player_controller.dart';

void main() {
  final song = Track(id: '1', title: 'Blue Hair', artist: 'TV Girl', uri: 'https://x/1', source: TrackSource.audius, durationSec: 200);

  test('remote state reads what the other device sent', () {
    final s = RemoteState.fromJson({
      'track': song.toJson(),
      'playing': true,
      'positionMs': 30000,
      'durationMs': 200000,
      'queue': [song.toJson(), null, 'junk'],
      'index': 0,
      'shuffle': true,
      'repeat': 'all',
      'from': 'Good Time',
    });
    expect(s.track, song);
    expect(s.queue, [song]);
    expect(s.shuffle, isTrue);
    expect(s.repeat, RepeatState.all);
    expect(s.from, 'Good Time');
  });

  test('position keeps moving while it plays, stops when paused, never passes the end', () {
    final at = DateTime(2026, 1, 1, 12);
    RemoteState make(bool playing) => RemoteState(
          track: song,
          playing: playing,
          positionMs: 10000,
          durationMs: 12000,
          queue: [song],
          index: 0,
          shuffle: false,
          repeat: RepeatState.off,
          from: null,
          receivedAt: at,
        );
    expect(make(true).positionAt(at.add(const Duration(seconds: 1))), const Duration(seconds: 11));
    expect(make(true).positionAt(at.add(const Duration(seconds: 9))), const Duration(seconds: 12));
    expect(make(false).positionAt(at.add(const Duration(seconds: 5))), const Duration(seconds: 10));
  });
}
