import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A newer Mutiny published on GitHub Releases.
class UpdateInfo {
  final String version;
  final int build;
  final String notes;
  final String pageUrl;
  final String? androidUrl;
  final String? windowsUrl;
  final String? iosUrl;

  const UpdateInfo({
    required this.version,
    required this.build,
    required this.notes,
    required this.pageUrl,
    this.androidUrl,
    this.windowsUrl,
    this.iosUrl,
  });

  /// URL of the file for the platform the app is running on.
  String? get platformUrl {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return androidUrl;
    if (Platform.isWindows) return windowsUrl;
    if (Platform.isIOS) return iosUrl;
    return null;
  }
}

/// Checks GitHub Releases for a newer build and installs it where the
/// platform allows: Android (system installer), Windows (swap files and
/// restart). iPhone can only be told about it; installing is via Sideloadly.
class Updater {
  static const repo = 'Ndaktauulacok/Mutiny';
  static const releasesPage = 'https://github.com/$repo/releases/latest';

  static Future<(String version, int build)> current() async {
    final info = await PackageInfo.fromPlatform();
    return (info.version, int.tryParse(info.buildNumber) ?? 0);
  }

  /// Tag "v1.0.42" → 42 (the GitHub Actions run number, also the build number).
  static int? buildFromTag(String tag) {
    final m = RegExp(r'(\d+)$').firstMatch(tag.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Returns the latest release if it is newer than this app, else null.
  static Future<UpdateInfo?> check({http.Client? client}) async {
    final c = client ?? http.Client();
    final res = await c
        .get(
          Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Mutiny'},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final latest = parseRelease(jsonDecode(res.body) as Map<String, dynamic>);
    if (latest == null) return null;
    final (_, build) = await current();
    return latest.build > build ? latest : null;
  }

  static UpdateInfo? parseRelease(Map<String, dynamic> j) {
    final tag = j['tag_name'] as String? ?? '';
    final build = buildFromTag(tag);
    if (build == null) return null;
    String? asset(String suffix) {
      for (final a in (j['assets'] as List? ?? const [])) {
        final m = a as Map;
        if ((m['name'] as String? ?? '').toLowerCase().endsWith(suffix)) {
          return m['browser_download_url'] as String?;
        }
      }
      return null;
    }

    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      build: build,
      notes: (j['body'] as String? ?? '').trim(),
      pageUrl: j['html_url'] as String? ?? releasesPage,
      androidUrl: asset('.apk'),
      windowsUrl: asset('.zip'),
      iosUrl: asset('.ipa'),
    );
  }

  /// Android: downloads the APK and opens the system installer.
  /// Emits download progress 0..1, then 1 when the installer opens.
  static Stream<double> installAndroid(String url) {
    return OtaUpdate()
        .execute(url, destinationFilename: 'Mutiny-Android.apk')
        .transform(StreamTransformer.fromHandlers(handleData: (e, sink) {
      switch (e.status) {
        case OtaStatus.DOWNLOADING:
          sink.add((double.tryParse(e.value ?? '') ?? 0) / 100);
        case OtaStatus.INSTALLING:
        case OtaStatus.INSTALLATION_DONE:
          sink.add(1);
          sink.close();
        case OtaStatus.CANCELED:
          sink.close();
        default:
          sink.addError(Exception(e.value ?? e.status.name));
      }
    }));
  }

  /// Windows: downloads the zip and swaps the files in place. Windows lets a
  /// running program's files be renamed (not overwritten), so each old file
  /// is moved aside as "*.mutiny-old", the new one written, and Mutiny
  /// restarts. The leftovers are deleted on the next start.
  static Stream<double> installWindows(String url) async* {
    final tmp = await getTemporaryDirectory();
    final zip = File('${tmp.path}${Platform.pathSeparator}Mutiny-update.zip');
    final client = http.Client();
    try {
      final req = await client.send(http.Request('GET', Uri.parse(url)));
      if (req.statusCode != 200) throw Exception('Download failed (${req.statusCode})');
      final total = req.contentLength ?? 0;
      var got = 0;
      final sink = zip.openWrite();
      await for (final chunk in req.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) yield 0.9 * got / total;
      }
      await sink.close();
    } finally {
      client.close();
    }

    applyUpdate(
      ZipDecoder().decodeBytes(await zip.readAsBytes()),
      appDir: File(Platform.resolvedExecutable).parent.path,
      exeName: p.basename(Platform.resolvedExecutable),
    );
    yield 0.98;
    try {
      zip.deleteSync();
    } catch (_) {}

    // Restart even if the update sheet is closed meanwhile.
    unawaited(_restartWindows(File(Platform.resolvedExecutable).parent.path));
    yield 1;
  }

  static const oldSuffix = '.mutiny-old';

  /// Writes the files of an update zip into [appDir]. Files that are in use
  /// are renamed to "*.<time>.mutiny-old" first. Returns how many were written.
  static int applyUpdate(Archive archive, {required String appDir, required String exeName}) {
    final files = [
      for (final f in archive.files)
        if (f.isFile) f,
    ];
    String norm(String n) => n.replaceAll('\\', '/');
    if (!files.any((f) => p.basename(norm(f.name)) == exeName)) {
      throw Exception('The download does not contain $exeName');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var written = 0;
    for (final f in files) {
      final parts = norm(f.name).split('/').where((s) => s.isNotEmpty && s != '.').toList();
      if (parts.isEmpty || parts.contains('..')) continue;
      final target = File(p.joinAll([appDir, ...parts]));
      target.parent.createSync(recursive: true);
      if (target.existsSync()) {
        try {
          target.deleteSync();
        } on FileSystemException {
          target.renameSync('${target.path}.$stamp$oldSuffix'); // in use: move aside
        }
      }
      target.writeAsBytesSync(f.content, flush: true);
      written++;
    }
    return written;
  }

  static Future<void> _restartWindows(String appDir) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await Process.start(Platform.resolvedExecutable, const [], workingDirectory: appDir, mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Deletes the old files left behind by the last update (Windows).
  static Future<void> cleanUpOldFiles() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.endsWith(oldSuffix)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
