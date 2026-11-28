/// Core data types shared by every screen.
library;

enum TrackSource { audius, radio, local }

class Track {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String? artworkUrl;
  final String? artworkLargeUrl;
  final int? durationSec;
  final String? genre;
  final int? playCount;
  final TrackSource source;

  /// Public web link (Audius) used for sharing.
  final String? permalink;

  /// Stream URL (Audius / radio) or file path (local).
  final String uri;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    required this.source,
    this.artistId,
    this.artworkUrl,
    this.artworkLargeUrl,
    this.durationSec,
    this.genre,
    this.playCount,
    this.permalink,
  });

  bool get isLive => source == TrackSource.radio;
  bool get isLocal => source == TrackSource.local;
  String? get bestArtwork => artworkLargeUrl ?? artworkUrl;

  /// Unique across sources, so an Audius id can never clash with a station id.
  String get key => '${source.name}:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'artworkUrl': artworkUrl,
        'artworkLargeUrl': artworkLargeUrl,
        'durationSec': durationSec,
        'genre': genre,
        'playCount': playCount,
        'source': source.name,
        'uri': uri,
        'permalink': permalink,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Unknown',
        artist: j['artist'] as String? ?? 'Unknown artist',
        artistId: j['artistId'] as String?,
        artworkUrl: j['artworkUrl'] as String?,
        artworkLargeUrl: j['artworkLargeUrl'] as String?,
        durationSec: j['durationSec'] as int?,
        genre: j['genre'] as String?,
        playCount: j['playCount'] as int?,
        source: TrackSource.values.firstWhere(
          (s) => s.name == j['source'],
          orElse: () => TrackSource.audius,
        ),
        uri: j['uri'] as String? ?? '',
        permalink: j['permalink'] as String?,
      );

  @override
  bool operator ==(Object other) => other is Track && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class Collection {
  final String id;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final int? trackCount;

  const Collection({
    required this.id,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
    this.trackCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
        'trackCount': trackCount,
      };

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Playlist',
        subtitle: j['subtitle'] as String? ?? '',
        artworkUrl: j['artworkUrl'] as String?,
        trackCount: j['trackCount'] as int?,
      );

  @override
  bool operator ==(Object other) => other is Collection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Artist {
  final String id;
  final String name;
  final String? avatarUrl;
  final int followers;
  final int trackCount;

  const Artist({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.followers = 0,
    this.trackCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarUrl': avatarUrl,
        'followers': followers,
        'trackCount': trackCount,
      };

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Artist',
        avatarUrl: j['avatarUrl'] as String?,
        followers: j['followers'] as int? ?? 0,
        trackCount: j['trackCount'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) => other is Artist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class UserPlaylist {
  final String id;
  String name;
  String description;

  /// Photo the user picked for the cover (file in app storage), or null
  /// for the automatic 4-artwork mosaic.
  String? coverPath;
  bool pinned;
  final List<Track> tracks;
  final DateTime created;
  DateTime updated;

  UserPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.created,
    this.description = '',
    this.coverPath,
    this.pinned = false,
    DateTime? updated,
  }) : updated = updated ?? created;

  String? get coverUrl {
    for (final t in tracks) {
      if (t.bestArtwork != null) return t.bestArtwork;
    }
    return null;
  }

  /// Up to four different artworks for the Spotify-style mosaic cover.
  List<String> get mosaic {
    final out = <String>[];
    for (final t in tracks) {
      final a = t.artworkUrl;
      if (a != null && !out.contains(a)) out.add(a);
      if (out.length == 4) break;
    }
    return out;
  }

  int get totalSeconds => tracks.fold(0, (s, t) => s + (t.durationSec ?? 0));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'coverPath': coverPath,
        'pinned': pinned,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Playlist',
        description: j['description'] as String? ?? '',
        coverPath: j['coverPath'] as String?,
        pinned: j['pinned'] as bool? ?? false,
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
        tracks: ((j['tracks'] as List?) ?? const [])
            .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// The person using Mutiny on this device.
class Profile {
  String name;
  String? avatarPath;
  final DateTime since;

  Profile({required this.name, this.avatarPath, DateTime? since}) : since = since ?? DateTime.now();

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Map<String, dynamic> toJson() => {'name': name, 'avatarPath': avatarPath, 'since': since.toIso8601String()};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: j['name'] as String? ?? 'Listener',
        avatarPath: j['avatarPath'] as String?,
        since: DateTime.tryParse(j['since'] as String? ?? ''),
      );
}

/// How often a song was played (for the profile's top songs / artists).
class PlayStat {
  final Track track;
  int plays;
  int seconds;
  DateTime last;

  PlayStat({required this.track, this.plays = 0, this.seconds = 0, DateTime? last}) : last = last ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'plays': plays,
        'seconds': seconds,
        'last': last.toIso8601String(),
      };

  factory PlayStat.fromJson(Map<String, dynamic> j) => PlayStat(
        track: Track.fromJson(Map<String, dynamic>.from(j['track'] as Map)),
        plays: j['plays'] as int? ?? 0,
        seconds: j['seconds'] as int? ?? 0,
        last: DateTime.tryParse(j['last'] as String? ?? ''),
      );
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String compactNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

/// Where the user last started playing from, shown on Home like Spotify's
/// "recents" grid: a playlist, Liked Songs, an artist, a mix or a station.
enum PlayContextType { playlist, liked, mySongs, remote, artist, genre, mix, flow, station }

class PlayContext {
  PlayContext({required this.type, required this.id, required this.title, this.subtitle = '', this.artworkUrl, this.data = const {}, DateTime? at})
      : at = at ?? DateTime.now();

  final PlayContextType type;

  /// Playlist id, artist id, genre name, … (unique within [type]).
  final String id;
  final String title;
  final String subtitle;
  final String? artworkUrl;

  /// What is needed to open it again (the Audius playlist, artist, station…).
  final Map<String, dynamic> data;
  final DateTime at;

  String get key => '${type.name}:$id';

  @override
  bool operator ==(Object other) => other is PlayContext && other.key == key;

  @override
  int get hashCode => key.hashCode;

  Map<String, dynamic> toJson() => {
        'source': 'ctx', // lets the sync merge tell items apart
        'id': key,
        'type': type.name,
        'cid': id,
        'title': title,
        'subtitle': subtitle,
        'art': artworkUrl,
        'data': data,
        'at': at.toIso8601String(),
      };

  static PlayContext? fromJson(Map<String, dynamic> j) {
    final type = PlayContextType.values.where((t) => t.name == j['type']).firstOrNull;
    if (type == null) return null;
    return PlayContext(
      type: type,
      id: j['cid'] as String? ?? '',
      title: j['title'] as String? ?? '',
      subtitle: j['subtitle'] as String? ?? '',
      artworkUrl: j['art'] as String?,
      data: Map<String, dynamic>.from((j['data'] as Map?) ?? const {}),
      at: DateTime.tryParse(j['at'] as String? ?? ''),
    );
  }
}
