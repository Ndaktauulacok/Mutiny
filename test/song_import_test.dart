import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mutiny/services/library_store.dart';
import 'package:mutiny/services/song_importer.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

const realFolder = '/mnt/user-data/uploads/Music neww';

void main() {
  group('file names', () {
    final cases = {
      'Bleachers - Isimo_320k.mp3': ('Bleachers', 'Isimo'),
      'girl in red - we fell in love in october (Lyrics)_320k.mp3': ('girl in red', 'we fell in love in october'),
      'JVKE - her (feat. Annika Wells)_320k.mp3': ('JVKE', 'her (feat. Annika Wells)'),
      'Lil Uzi Vert, Oh Wonder - The Way Life Goes _ Lyrics_320k (1).mp3': ('Lil Uzi Vert, Oh Wonder', 'The Way Life Goes'),
      'Lil Uzi Vert, Oh Wonder - The Way Life Goes _ Lyrics_320k.mp3': ('Lil Uzi Vert, Oh Wonder', 'The Way Life Goes'),
      'Lost Within the End (Slowed)_320k.mp3': ('', 'Lost Within the End (Slowed)'),
      'Malcolm Todd - Chest Pain (I Love) (Lyrics)_320k.mp3': ('Malcolm Todd', 'Chest Pain (I Love)'),
      'Shut up My Moms Calling (Sped up)_320k.mp3': ('', 'Shut up My Moms Calling (Sped up)'),
      'The Neighbourhood - Softcore (Official Audio)_320k.mp3': ('The Neighbourhood', 'Softcore'),
      'TV Girl - Blue Hair_320k.mp3': ('TV Girl', 'Blue Hair'),
      'Artist - Song (Official Music Video) [HD].m4a': ('Artist', 'Song'),
    };
    cases.forEach((file, want) {
      test(file, () {
        final got = SongImporter.cleanFileName(file);
        expect((got.artist, got.title), want);
      });
    });
    test('search title drops speed edits', () {
      expect(SongImporter.searchTitle('Shut up My Moms Calling (Sped up)'), 'Shut up My Moms Calling');
      expect(SongImporter.searchTitle('her (feat. Annika Wells)'), 'her (feat. Annika Wells)');
    });
  });

  test('catalogue match needs the same song and artist', () {
    final r = {'trackName': 'The Way Life Goes (feat. Oh Wonder)', 'artistName': 'Lil Uzi Vert'};
    expect(SongImporter.matches(r, title: 'The Way Life Goes', artist: 'Lil Uzi Vert, Oh Wonder'), isTrue);
    expect(SongImporter.matches(r, title: 'The Way Life Goes', artist: 'Taylor Swift'), isFalse);
    expect(SongImporter.matches(r, title: 'Life', artist: ''), isFalse);
  });

  test('reads length from a real file', () async {
    final f = File('$realFolder/TV Girl - Blue Hair_320k.mp3');
    if (!f.existsSync()) return markTestSkipped('sample file not here');
    final tags = await SongImporter.readTags(f.path);
    expect(tags.durationSec, inInclusiveRange(150, 400));
  });

  test('imports a folder: names, covers, duplicates', () async {
    final real = Directory(realFolder);
    if (!real.existsSync()) return markTestSkipped('sample files not here');
    final tmp = Directory.systemTemp.createTempSync('mutiny_import');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({});
    final lib = LibraryStore();
    await lib.load();

    // The same file twice, like "song.mp3" and "song (1).mp3".
    final blue = File('$realFolder/TV Girl - Blue Hair_320k.mp3');
    final copy = blue.copySync('${tmp.path}/TV Girl - Blue Hair_320k (1).mp3');
    final itunes = MockClient((req) async {
      final term = req.url.queryParameters['term'] ?? '';
      final results = [
        if (term.contains('Blue Hair')) {'trackName': 'Blue Hair', 'artistName': 'TV Girl', 'artworkUrl100': 'https://a/100x100bb.jpg', 'trackTimeMillis': 180000},
        if (term.contains('Lost Within')) {'trackName': 'Lost Within the End (Slowed)', 'artistName': 'wenznv', 'artworkUrl100': 'https://b/100x100bb.jpg', 'trackTimeMillis': 200000},
      ];
      return http.Response(jsonEncode({'results': results}), 200);
    });
    final steps = <int>[];
    final report = await lib.importSongFiles(
      [blue.path, copy.path, '$realFolder/Lost Within the End (Slowed)_320k.mp3', '${tmp.path}/missing.mp3'],
      client: itunes,
      onProgress: (d, _) => steps.add(d),
    );
    expect(report.added, 2);
    expect(report.duplicates, 1);
    expect(report.failed, ['missing.mp3']);
    expect(steps.last, 4);

    final byTitle = {for (final t in lib.localTracks) t.title: t};
    expect(byTitle['Blue Hair']!.artist, 'TV Girl');
    expect(byTitle['Blue Hair']!.artworkUrl, 'https://a/600x600bb.jpg');
    expect(byTitle['Blue Hair']!.durationSec, inInclusiveRange(150, 400));
    expect(File(byTitle['Blue Hair']!.uri).existsSync(), isTrue);
    // No artist in the file name: taken from the catalogue.
    expect(byTitle['Lost Within the End (Slowed)']!.artist, 'wenznv');

    // Importing again adds nothing.
    final again = await lib.importSongFiles([blue.path], client: itunes);
    expect(again.added, 0);
    expect(again.duplicates, 1);
    tmp.deleteSync(recursive: true);
  });
}
