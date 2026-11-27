import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Free internet radio from the community-run Radio Browser directory
/// (https://www.radio-browser.info). No key needed.
class RadioApi {
  static const _mirrors = [
    'https://de1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
    'https://fi1.api.radio-browser.info',
  ];

  static const countries = <(String code, String label)>[
    ('MY', 'Malaysia'),
    ('', 'Worldwide'),
    ('SG', 'Singapore'),
    ('ID', 'Indonesia'),
    ('US', 'USA'),
    ('GB', 'UK'),
    ('JP', 'Japan'),
    ('KR', 'Korea'),
  ];

  final http.Client _client;
  RadioApi([http.Client? client]) : _client = client ?? http.Client();

  Future<List<dynamic>> _get(String path, Map<String, String> query) async {
    Object? lastError;
    for (final host in _mirrors) {
      try {
        final uri = Uri.parse('$host$path').replace(queryParameters: query);
        final res = await _client
            .get(uri, headers: {'User-Agent': 'Mutiny/1.0'})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Radio directory unavailable ($lastError)');
  }

  Future<List<Track>> topStations({String countryCode = '', int limit = 40}) async {
    final query = {
      'limit': '$limit',
      'order': 'clickcount',
      'reverse': 'true',
      'hidebroken': 'true',
    };
    final data = countryCode.isEmpty
        ? await _get('/json/stations/search', query)
        : await _get('/json/stations/bycountrycodeexact/$countryCode', query);
    return parseStations(data);
  }

  Future<List<Track>> search(String name) async => parseStations(await _get(
        '/json/stations/search',
        {
          'name': name,
          'limit': '40',
          'order': 'clickcount',
          'reverse': 'true',
          'hidebroken': 'true',
        },
      ));

  static List<Track> parseStations(List<dynamic> data) {
    final seen = <String>{};
    final out = <Track>[];
    for (final raw in data.whereType<Map>()) {
      final s = Map<String, dynamic>.from(raw);
      final url = (s['url_resolved'] as String?)?.trim() ?? '';
      final name = (s['name'] as String?)?.trim() ?? '';
      if (url.isEmpty || name.isEmpty || !seen.add(name.toLowerCase())) continue;
      final favicon = (s['favicon'] as String?)?.trim();
      final tags = (s['tags'] as String? ?? '')
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .take(2)
          .join(' · ');
      out.add(Track(
        id: s['stationuuid'] as String? ?? name,
        title: name,
        artist: tags.isNotEmpty ? tags : (s['country'] as String? ?? 'Live radio'),
        artworkUrl: (favicon == null || favicon.isEmpty) ? null : favicon,
        source: TrackSource.radio,
        uri: url,
        genre: 'Radio',
      ));
    }
    return out;
  }
}
