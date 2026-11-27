import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/models/models.dart';
import 'package:mutiny/services/audius_api.dart';
import 'package:mutiny/services/library_store.dart';
import 'package:mutiny/services/lyrics_api.dart';
import 'package:mutiny/services/radio_api.dart';
import 'package:mutiny/services/updater.dart';
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

  test('Release tags map to build numbers and platform files', () {
    expect(Updater.buildFromTag('v1.0.42'), 42);
    expect(Updater.buildFromTag('nightly'), isNull);
    final info = Updater.parseRelease({
      'tag_name': 'v1.0.7',
      'body': 'Faster search',
      'html_url': 'https://github.com/x/y/releases/tag/v1.0.7',
      'assets': [
        {'name': 'Mutiny-Android.apk', 'browser_download_url': 'https://d/a.apk'},
        {'name': 'Mutiny-Windows.zip', 'browser_download_url': 'https://d/w.zip'},
        {'name': 'Mutiny-iOS.ipa', 'browser_download_url': 'https://d/i.ipa'},
      ],
    })!;
    expect(info.version, '1.0.7');
    expect(info.build, 7);
    expect(info.androidUrl, 'https://d/a.apk');
    expect(info.windowsUrl, 'https://d/w.zip');
    expect(info.iosUrl, 'https://d/i.ipa');
  });

  test('LRC lyrics parse into timed lines', () {
    final lines = LyricsApi.parseLrc('[00:12.50] Look at the stars\n[00:17.00]Look how they shine\n[01:02.34]\nno stamp');
    expect(lines, hasLength(3));
    expect(lines.first.time, const Duration(milliseconds: 12500));
    expect(lines.first.text, 'Look at the stars');
    expect(lines.last.time, const Duration(milliseconds: 62340));
    expect(LyricsApi.cleanTitle('Yellow (Official Video) ft. Someone'), 'Yellow');
  });

  test('Playlists keep cover, description, order and pins; stats rank songs', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = LibraryStore();
    await lib.load();
    Track t(String id, String artist) =>
        Track(id: id, title: 'Song $id', artist: artist, uri: 'u$id', source: TrackSource.audius, durationSec: 200);
    final p = lib.createPlaylist('Road trip');
    expect(lib.addAllToPlaylist(p, [t('1', 'A'), t('2', 'B'), t('3', 'A'), t('1', 'A')]), 3);
    lib.movePlaylistTrack(p, 0, 2);
    expect(p.tracks.map((e) => e.id), ['2', '3', '1']);
    lib.editPlaylist(p, name: 'Road trip 2026', description: 'Kedah to KL');
    lib.togglePin(p);
    final copy = lib.duplicatePlaylist(p);
    expect(copy.tracks, hasLength(3));
    expect(copy.name, 'Road trip 2026 (copy)');

    lib.setProfileName('Amreel');
    lib.toggleFollow(const Artist(id: 'a1', name: 'Raar'));
    lib.toggleSavePlaylist(const Collection(id: 'c1', title: 'Hot & New', subtitle: 'Audius'));
    lib.recordListen(t('1', 'A'), 120);
    lib.recordListen(t('1', 'A'), 90);
    lib.recordListen(t('2', 'B'), 40);
    lib.recordListen(t('3', 'A'), 10); // under 30s: time counts, not a play

    final again = LibraryStore();
    await again.load();
    final saved = again.playlists.firstWhere((x) => x.name == 'Road trip 2026');
    expect(saved.description, 'Kedah to KL');
    expect(saved.pinned, isTrue);
    expect(saved.tracks.map((e) => e.id), ['2', '3', '1']);
    expect(again.profile.name, 'Amreel');
    expect(again.profile.initials, 'A');
    expect(again.followedArtists.single.name, 'Raar');
    expect(again.savedPlaylists.single.title, 'Hot & New');
    expect(again.topTracks().first.track.id, '1');
    expect(again.topTracks().first.plays, 2);
    expect(again.topTracks().any((s) => s.track.id == '3'), isFalse);
    expect(again.topArtists().first.$1, 'A');
    expect(again.totalListenMinutes, 4);
  });

  test('Own songs: add with lyrics, use in playlists, edit everywhere, delete', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = LibraryStore();
    await lib.load();
    lib.setProfileName('Amreel');
    final song = lib.addOwnSong(
      audioPath: '/tmp/does-not-matter.mp3',
      title: 'Lagu Raya Kita',
      artist: '',
      lyrics: '[00:05] Selamat hari raya\n[00:10] Maaf zahir batin',
      durationSec: 180,
    );
    expect(song.isLocal, isTrue);
    expect(song.artist, 'Amreel'); // defaults to the profile name
    expect(lib.localTracks.first, song);
    expect(LyricsApi.parseLrc(lib.lyricsFor(song)!), hasLength(2));

    final p = lib.createPlaylist('Raya');
    expect(lib.addToPlaylist(p, song), isTrue);
    lib.toggleLike(song);

    final edited = lib.updateOwnSong(song, title: 'Lagu Raya 2026', artist: 'Amreel & Fahri', lyrics: 'Plain words');
    expect(lib.localTracks.first.title, 'Lagu Raya 2026');
    expect(p.tracks.single.title, 'Lagu Raya 2026');
    expect(lib.liked.single.artist, 'Amreel & Fahri');
    expect(lib.lyricsFor(edited), 'Plain words');

    final again = LibraryStore();
    await again.load();
    expect(again.localTracks.single.title, 'Lagu Raya 2026');
    expect(again.playlists.single.tracks.single.title, 'Lagu Raya 2026');
    expect(again.lyricsFor(again.localTracks.single), 'Plain words');

    await again.removeLocal(again.localTracks.single);
    expect(again.localTracks, isEmpty);
    expect(again.playlists.single.tracks, isEmpty);
    expect(again.liked, isEmpty);
    expect(again.lyricsFor(edited), isNull);
  });
}
