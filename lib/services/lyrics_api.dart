import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

class Lyrics {
  /// Time-synced lines (empty when only plain lyrics exist).
  final List<LyricLine> synced;
  final String plain;
  const Lyrics({this.synced = const [], this.plain = ''});

  bool get isSynced => synced.isNotEmpty;
  bool get isEmpty => synced.isEmpty && plain.trim().isEmpty;
}

/// Lyrics from LRCLIB (https://lrclib.net), a free open lyrics database.
/// Independent songs on Audius often have no lyrics there; popular songs
/// (e.g. your own MP3s) usually do.
class LyricsApi {
  static final _cache = <String, Lyrics?>{};
  final http.Client _client;
  LyricsApi([http.Client? client]) : _client = client ?? http.Client();

  Future<Lyrics?> find(Track t) async {
    if (t.isLive) return null;
    if (_cache.containsKey(t.key)) return _cache[t.key];
    final title = cleanTitle(t.title);
    final artist = t.artist == 'Unknown artist' ? '' : t.artist;
    Lyrics? result;
    try {
      // 1. Exact match by title + artist (+ duration when known).
      if (artist.isNotEmpty) {
        final res = await _client.get(
          Uri.https('lrclib.net', '/api/get', {
            'track_name': title,
            'artist_name': artist,
            if (t.durationSec != null) 'duration': '${t.durationSec}',
          }),
          headers: {'User-Agent': 'Mutiny (https://github.com/Ndaktauulacok/Mutiny)'},
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) result = _parse(jsonDecode(res.body) as Map<String, dynamic>);
      }
      // 2. Search, preferring a result whose length matches.
      if (result == null || result.isEmpty) {
        final res = await _client.get(
          Uri.https('lrclib.net', '/api/search', {'q': '$title $artist'.trim()}),
          headers: {'User-Agent': 'Mutiny (https://github.com/Ndaktauulacok/Mutiny)'},
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final list = (jsonDecode(res.body) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          if (t.durationSec != null) {
            list.sort((a, b) => ((a['duration'] as num? ?? 0) - t.durationSec!).abs().compareTo(((b['duration'] as num? ?? 0) - t.durationSec!).abs()));
            list.removeWhere((e) => ((e['duration'] as num? ?? 0) - t.durationSec!).abs() > 8);
          }
          for (final e in list) {
            final l = _parse(e);
            if (l != null && !l.isEmpty) {
              result = l;
              break;
            }
          }
        }
      }
    } catch (_) {
      return null; // offline: don't cache, try again later
    }
    return _cache[t.key] = (result == null || result.isEmpty) ? null : result;
  }

  static Lyrics? _parse(Map<String, dynamic> j) {
    if (j['instrumental'] == true) return const Lyrics(plain: '♪ Instrumental ♪');
    return Lyrics(
      synced: parseLrc(j['syncedLyrics'] as String? ?? ''),
      plain: j['plainLyrics'] as String? ?? '',
    );
  }

  /// "[01:02.34] words" → LyricLine(62.34s, "words").
  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    final re = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    for (final raw in const LineSplitter().convert(lrc)) {
      final stamps = re.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final text = raw.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final ms = (int.parse(m.group(1)!) * 60000 + double.parse(m.group(2)!) * 1000).round();
        out.add(LyricLine(Duration(milliseconds: ms), text));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// Drops "(Official Video)", "[Remix]", "ft. X" etc. for better matches.
  static String cleanTitle(String title) => title
      .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '')
      .replaceAll(RegExp(r'\s+(ft\.?|feat\.?)\s+.*$', caseSensitive: false), '')
      .trim();
}
