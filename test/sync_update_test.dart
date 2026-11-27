import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutiny/services/cloud_sync.dart';
import 'package:mutiny/services/updater.dart';

void main() {
  group('cloud file names', () {
    test('the song that blocked sync gets a valid storage name', () {
      expect(CloudSync.safeKeyName('1795797615828_14 - twenty one pilots - Drag Path.mp3'),
          '1795797615828_14_-_twenty_one_pilots_-_Drag_Path.mp3');
    });
    test('accents, symbols and odd extensions are cleaned', () {
      expect(CloudSync.safeKeyName('Sigur Rós — Untitled #9 (live).FLAC'), 'Sigur_R_s_Untitled_9_live.flac');
      expect(CloudSync.safeKeyName('%%%.jpg'), 'file.jpg');
      expect(CloudSync.safeKeyName('avatar_1795796614763.jpg'), 'avatar_1795796614763.jpg');
    });
    test('only plain characters remain', () {
      final out = CloudSync.safeKeyName("weird 名前 %20 [x] 'y'.m4a");
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(out), isTrue);
      expect(out.endsWith('.m4a'), isTrue);
    });
  });

  group('Windows update', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mutiny_upd'));
    tearDown(() => dir.deleteSync(recursive: true));

    Archive zipOf(Map<String, String> files) {
      final a = Archive();
      files.forEach((name, text) => a.addFile(ArchiveFile.string(name, text)));
      return ZipDecoder().decodeBytes(ZipEncoder().encode(a));
    }

    test('replaces files, including in subfolders and backslash paths', () {
      File('${dir.path}/mutiny.exe').writeAsStringSync('old exe');
      Directory('${dir.path}/data').createSync();
      File('${dir.path}/data/app.so').writeAsStringSync('old app');
      final n = Updater.applyUpdate(
        zipOf({'mutiny.exe': 'new exe', 'data/app.so': 'new app', 'data\\flutter_assets\\a.txt': 'asset'}),
        appDir: dir.path,
        exeName: 'mutiny.exe',
      );
      expect(n, 3);
      expect(File('${dir.path}/mutiny.exe').readAsStringSync(), 'new exe');
      expect(File('${dir.path}/data/app.so').readAsStringSync(), 'new app');
      expect(File('${dir.path}/data/flutter_assets/a.txt').readAsStringSync(), 'asset');
    });

    test('refuses a zip without the app and ignores escaping paths', () {
      expect(() => Updater.applyUpdate(zipOf({'readme.txt': 'x'}), appDir: dir.path, exeName: 'mutiny.exe'),
          throwsException);
      Updater.applyUpdate(zipOf({'mutiny.exe': 'x', '../evil.txt': 'x'}), appDir: dir.path, exeName: 'mutiny.exe');
      expect(File('${dir.parent.path}/evil.txt').existsSync(), isFalse);
    });
  });
}
