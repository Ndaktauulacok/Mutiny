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
}

class UserPlaylist {
  final String id;
  String name;
  final List<Track> tracks;
  final DateTime created;

  UserPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.created,
  });

  String? get coverUrl {
    for (final t in tracks) {
      if (t.bestArtwork != null) return t.bestArtwork;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Playlist',
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        tracks: ((j['tracks'] as List?) ?? const [])
            .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
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
