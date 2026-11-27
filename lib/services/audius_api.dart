import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Free, legal music streaming from Audius (https://audius.co).
/// No API key is needed; Audius only asks for an app name.
class AudiusApi {
  static const appName = 'Mutiny';
  static const _host = 'https://api.audius.co/v1';

  final http.Client _client;
  AudiusApi([http.Client? client]) : _client = client ?? http.Client();

  static const genres = <String>[
    'Electronic',
    'Hip-Hop/Rap',
    'Lo-Fi',
    'Pop',
    'R&B/Soul',
    'Alternative',
    'House',
    'Ambient',
    'Rock',
    'Acoustic',
    'Jazz',
    'Techno',
    'Dubstep',
    'Trap',
    'Soundtrack',
    'Latin',
  ];

  Uri _uri(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('$_host$path').replace(queryParameters: {...query, 'app_name': appName});

  Future<List<dynamic>> _getList(String path, [Map<String, String> query = const {}]) async {
    final res = await _client.get(_uri(path, query)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw AudiusException('Audius returned ${res.statusCode}');
    }
    final body = jsonDecode(res.body);
    return (body is Map && body['data'] is List) ? body['data'] as List : const [];
  }

  Future<List<Track>> trending({String? genre, String time = 'week', int limit = 30}) async {
    final data = await _getList('/tracks/trending', {
      'time': time,
      'limit': '$limit',
      'genre': ?genre,
    });
    return parseTracks(data);
  }

  Future<List<Track>> undergroundTrending({int limit = 20}) async =>
      parseTracks(await _getList('/tracks/trending/underground', {'limit': '$limit'}));

  Future<List<Track>> searchTracks(String query) async =>
      parseTracks(await _getList('/tracks/search', {'query': query, 'limit': '30'}));

  Future<List<Artist>> searchArtists(String query) async =>
      (await _getList('/users/search', {'query': query, 'limit': '20'}))
          .whereType<Map>()
          .map((u) => parseArtist(Map<String, dynamic>.from(u)))
          .toList();

  Future<List<Collection>> searchPlaylists(String query) async =>
      (await _getList('/playlists/search', {'query': query, 'limit': '20'}))
          .whereType<Map>()
          .map((p) => parsePlaylist(Map<String, dynamic>.from(p)))
          .toList();

  Future<List<Collection>> trendingPlaylists({int limit = 12}) async =>
      (await _getList('/playlists/trending', {'limit': '$limit', 'time': 'week'}))
          .whereType<Map>()
          .map((p) => parsePlaylist(Map<String, dynamic>.from(p)))
          .toList();

  Future<List<Track>> playlistTracks(String id) async =>
      parseTracks(await _getList('/playlists/$id/tracks'));

  Future<List<Track>> artistTracks(String id) async => parseTracks(
        await _getList('/users/$id/tracks', {'limit': '50', 'sort_method': 'plays'}),
      );

  static String streamUrl(String trackId) => '$_host/tracks/$trackId/stream?app_name=$appName';

  static List<Track> parseTracks(List<dynamic> data) => data
      .whereType<Map>()
      .map((t) => Map<String, dynamic>.from(t))
      .where((t) => t['is_streamable'] != false && t['is_stream_gated'] != true)
      .map(parseTrack)
      .toList();

  static Track parseTrack(Map<String, dynamic> t) {
    final user = t['user'] is Map ? Map<String, dynamic>.from(t['user'] as Map) : const {};
    final art = t['artwork'] is Map ? Map<String, dynamic>.from(t['artwork'] as Map) : const {};
    final id = '${t['id']}';
    return Track(
      id: id,
      title: (t['title'] as String?)?.trim() ?? 'Untitled',
      artist: (user['name'] as String?)?.trim() ?? 'Unknown artist',
      artistId: user['id'] as String?,
      artworkUrl: art['480x480'] as String? ?? art['150x150'] as String?,
      artworkLargeUrl: art['1000x1000'] as String? ?? art['480x480'] as String?,
      durationSec: (t['duration'] as num?)?.toInt(),
      genre: t['genre'] as String?,
      playCount: (t['play_count'] as num?)?.toInt(),
      source: TrackSource.audius,
      uri: streamUrl(id),
    );
  }

  static Artist parseArtist(Map<String, dynamic> u) {
    final pic = u['profile_picture'] is Map
        ? Map<String, dynamic>.from(u['profile_picture'] as Map)
        : const {};
    return Artist(
      id: '${u['id']}',
      name: u['name'] as String? ?? 'Artist',
      avatarUrl: pic['480x480'] as String? ?? pic['150x150'] as String?,
      followers: (u['follower_count'] as num?)?.toInt() ?? 0,
      trackCount: (u['track_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Collection parsePlaylist(Map<String, dynamic> p) {
    final art = p['artwork'] is Map ? Map<String, dynamic>.from(p['artwork'] as Map) : const {};
    final user = p['user'] is Map ? Map<String, dynamic>.from(p['user'] as Map) : const {};
    return Collection(
      id: '${p['id']}',
      title: p['playlist_name'] as String? ?? 'Playlist',
      subtitle: user['name'] as String? ?? '',
      artworkUrl: art['480x480'] as String? ?? art['150x150'] as String?,
      trackCount: (p['track_count'] as num?)?.toInt(),
    );
  }
}

class AudiusException implements Exception {
  final String message;
  AudiusException(this.message);
  @override
  String toString() => message;
}
