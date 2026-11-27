import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
/// platform allows: Android (system installer), Windows (replace files and
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

  /// Windows: downloads the zip, then a small PowerShell script waits for
  /// Mutiny to close, copies the new files over this folder and restarts it.
  static Stream<double> installWindows(String url) async* {
    final tmp = await getTemporaryDirectory();
    final zip = File('${tmp.path}\\Mutiny-update.zip');
    final req = await http.Client().send(http.Request('GET', Uri.parse(url)));
    if (req.statusCode != 200) throw Exception('Download failed (${req.statusCode})');
    final total = req.contentLength ?? 0;
    var got = 0;
    final sink = zip.openWrite();
    await for (final chunk in req.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) yield got / total;
    }
    await sink.close();

    final appDir = File(Platform.resolvedExecutable).parent.path;
    final extractDir = '${tmp.path}\\Mutiny-update';
    final script = File('${tmp.path}\\mutiny-update.ps1');
    await script.writeAsString('''
\$ErrorActionPreference = "Stop"
Wait-Process -Id $pid -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
if (Test-Path "$extractDir") { Remove-Item "$extractDir" -Recurse -Force }
Expand-Archive -Path "${zip.path}" -DestinationPath "$extractDir" -Force
Copy-Item -Path "$extractDir\\*" -Destination "$appDir" -Recurse -Force
Start-Process "$appDir\\${File(Platform.resolvedExecutable).uri.pathSegments.last}"
''');
    await Process.start(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path],
      mode: ProcessStartMode.detached,
    );
    yield 1;
    exit(0);
  }
}
