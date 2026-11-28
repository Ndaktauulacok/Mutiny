import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Turns music files into tidy songs: a clean title and artist from the file
/// name and tags, a proper cover from the iTunes catalogue (or the picture
/// inside the file), and the length so synced lyrics can be found.
abstract final class SongImporter {
  static final _junk = RegExp(
    r'(official\s+(music\s+)?(video|audio|visuali[sz]er|lyric\s+video)|lyrics?(\s+video)?|audio|visuali[sz]er|hd|hq|4k|explicit|clean|mv|m/v)',
    caseSensitive: false,
  );

  /// "Malcolm Todd - Sweet Boy (Lyrics)_320k (1).mp3" → ("Malcolm Todd", "Sweet Boy").
  /// Keeps meaningful parts such as "(feat. X)", "(Sped up)" and "(Slowed)".
  static ({String artist, String title}) cleanFileName(String fileName) {
    var s = fileName.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '');
    s = s.replaceFirst(RegExp(r'\s*\(\d+\)$'), ''); // "(1)" from a second download
    s = s.replaceAll(RegExp(r'[_ ]\d{2,3}k(bps)?\b', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');
    s = s.replaceAll(RegExp(r'\s*[\(\[]\s*' + _junk.pattern + r'\s*[\)\]]', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'\s*[_|]\s*' + _junk.pattern + r'\s*$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[\s_-]+|[\s_-]+$'), '');
    final dash = s.indexOf(' - ');
    if (dash > 0) {
      return (artist: s.substring(0, dash).trim(), title: s.substring(dash + 3).trim());
    }
    return (artist: '', title: s);
  }

  /// The title without "(Sped up)", "(Slowed)"… for looking it up.
  static String searchTitle(String title) => title
      .replaceAll(RegExp(r'\s*[\(\[](sped\s*up|slowed|slowed\s*\+\s*reverb|reverb|nightcore|remix)[^\)\]]*[\)\]]', caseSensitive: false), '')
      .trim();

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'\b(feat|ft)\.?\b.*'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// True when an iTunes result is the same song (and artist, if known).
  static bool matches(Map<String, dynamic> r, {required String title, required String artist}) {
    final want = norm(searchTitle(title));
    final got = norm(r['trackName'] as String? ?? '');
    if (want.isEmpty || got.isEmpty) return false;
    final titleOk = got == want || (want.length > 3 && got.startsWith(want));
    if (!titleOk) return false;
    if (artist.isEmpty) return true;
    final ra = norm(r['artistName'] as String? ?? '');
    return artist.split(RegExp(r',|&| x ', caseSensitive: false)).map(norm).where((a) => a.isNotEmpty).any((a) => ra.contains(a) || a.contains(ra));
  }

  /// Looks the song up in the free iTunes catalogue: cover (600 px),
  /// proper artist name and length. Null when nothing matches well.
  static Future<CatalogMatch?> lookup({required String title, required String artist, http.Client? client}) async {
    final c = client ?? http.Client();
    final t = searchTitle(title);
    final queries = [
      if (artist.isNotEmpty) '${artist.split(',').first.trim()} $t',
      t,
    ];
    for (final q in queries) {
      try {
        final res = await c
            .get(Uri.https('itunes.apple.com', '/search', {'term': q, 'entity': 'song', 'limit': '25'}), headers: {'User-Agent': 'Mutiny'})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final results = ((jsonDecode(res.body) as Map)['results'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e));
        for (final r in results) {
          if (matches(r, title: title, artist: artist)) {
            final art = r['artworkUrl100'] as String?;
            return CatalogMatch(
              artist: r['artistName'] as String? ?? artist,
              coverUrl: art?.replaceFirst('100x100bb', '600x600bb'),
              durationSec: ((r['trackTimeMillis'] as num?) ?? 0) ~/ 1000,
            );
          }
        }
      } catch (_) {
        // offline or slow: try the next query
      }
    }
    return null;
  }

  /// Reads the tags inside a music file (in the background).
  static Future<FileTags> readTags(String path) => compute(_readTags, path);

  static FileTags _readTags(String path) {
    try {
      final m = readMetadata(File(path), getImage: true);
      final pic = m.pictures.isEmpty ? null : m.pictures.first;
      return FileTags(
        title: m.title?.trim(),
        artist: m.artist?.trim(),
        durationSec: m.duration?.inSeconds,
        cover: pic?.bytes,
        coverType: pic?.mimetype,
      );
    } catch (_) {
      return const FileTags();
    }
  }
}

class CatalogMatch {
  const CatalogMatch({required this.artist, this.coverUrl, this.durationSec});
  final String artist;
  final String? coverUrl;
  final int? durationSec;
}

class FileTags {
  const FileTags({this.title, this.artist, this.durationSec, this.cover, this.coverType});
  final String? title;
  final String? artist;
  final int? durationSec;
  final Uint8List? cover;
  final String? coverType;
}

class ImportReport {
  int added = 0;
  int duplicates = 0;
  int withCover = 0;
  final failed = <String>[];
}
