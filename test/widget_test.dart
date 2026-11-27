import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/models/models.dart';
import 'package:mutiny/services/audius_api.dart';
import 'package:mutiny/services/library_store.dart';
import 'package:mutiny/services/radio_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Track survives a JSON round trip', () {
    const t = Track(
      id: 'abc',
      title: 'Song',
      artist: 'Artist',
      uri: 'https://x/y',
      source: TrackSource.audius,
      artistId: 'u1',
      durationSec: 200,
    );
    final back = Track.fromJson(t.toJson());
    expect(back, t);
    expect(back.title, 'Song');
    expect(back.durationSec, 200);
    expect(back.source, TrackSource.audius);
  });

  test('Audius track parsing skips gated tracks and builds stream URLs', () {
    final tracks = AudiusApi.parseTracks([
      {
        'id': 'M2l69g9',
        'title': ' Night Drive ',
        'duration': 173,
        'user': {'id': 'u9', 'name': 'Raar'},
        'artwork': {'480x480': 'https://a/480.jpg', '1000x1000': 'https://a/1000.jpg'},
      },
      {'id': 'gated', 'title': 'Paid', 'is_stream_gated': true, 'user': {'name': 'x'}},
    ]);
    expect(tracks, hasLength(1));
    expect(tracks.first.title, 'Night Drive');
    expect(tracks.first.artist, 'Raar');
    expect(tracks.first.bestArtwork, 'https://a/1000.jpg');
    expect(tracks.first.uri, contains('/tracks/M2l69g9/stream'));
    expect(tracks.first.uri, contains('app_name=Mutiny'));
  });

  test('Radio stations are de-duplicated and need a stream URL', () {
    final stations = RadioApi.parseStations([
      {'stationuuid': '1', 'name': 'Sinar FM', 'url_resolved': 'https://s/1.m3u8', 'tags': 'malay,pop,hits'},
      {'stationuuid': '2', 'name': 'sinar fm', 'url_resolved': 'https://s/2.m3u8'},
      {'stationuuid': '3', 'name': 'Broken', 'url_resolved': ''},
    ]);
    expect(stations, hasLength(1));
    expect(stations.first.isLive, isTrue);
    expect(stations.first.artist, 'malay · pop');
  });

  test('File names become artist and title', () {
    expect(LibraryStore.parseFileName('Hindia - Evaluasi.mp3'), ('Hindia', 'Evaluasi'));
    expect(LibraryStore.parseFileName('my_song.flac'), ('Unknown artist', 'my song'));
  });

  test('Library likes, playlists and history persist', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = LibraryStore();
    await lib.load();
    const song = Track(id: '1', title: 'A', artist: 'B', uri: 'u', source: TrackSource.audius);
    const station = Track(id: 's', title: 'FM', artist: 'Live', uri: 'r', source: TrackSource.radio);

    expect(lib.toggleLike(song), isTrue);
    expect(lib.toggleLike(station), isTrue);
    expect(lib.liked, [song]);
    expect(lib.stations, [station]);

    final p = lib.createPlaylist('Gym');
    expect(lib.addToPlaylist(p, song), isTrue);
    expect(lib.addToPlaylist(p, song), isFalse);
    lib.addRecent(song);
    lib.addSearch('lofi');

    final reloaded = LibraryStore();
    await reloaded.load();
    expect(reloaded.liked.single.title, 'A');
    expect(reloaded.stations.single.isLive, isTrue);
    expect(reloaded.playlists.single.name, 'Gym');
    expect(reloaded.playlists.single.tracks.single, song);
    expect(reloaded.recent.single, song);
    expect(reloaded.recentSearches, ['lofi']);
  });
}
