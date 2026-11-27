import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Everything the user keeps: liked songs, playlists, saved stations,
/// imported files, listening history and recent searches.
/// Stored on the device only.
class LibraryStore extends ChangeNotifier {
  static const _kLiked = 'mutiny.liked';
  static const _kPlaylists = 'mutiny.playlists';
  static const _kStations = 'mutiny.stations';
  static const _kLocal = 'mutiny.local';
  static const _kRecent = 'mutiny.recent';
  static const _kSearches = 'mutiny.searches';
  static const _kProfile = 'mutiny.profile';
  static const _kArtists = 'mutiny.artists';
  static const _kSavedPlaylists = 'mutiny.savedPlaylists';
  static const _kStats = 'mutiny.stats';
  static const _kLyrics = 'mutiny.lyrics';

  SharedPreferences? _prefs;

  final List<Track> liked = [];
  final List<UserPlaylist> playlists = [];
  final List<Track> stations = [];
  final List<Track> localTracks = [];
  final List<Track> recent = [];
  final List<String> recentSearches = [];
  final List<Artist> followedArtists = [];
  final List<Collection> savedPlaylists = [];
  final Map<String, PlayStat> stats = {};
  Profile profile = Profile(name: 'Listener');

  /// Lyrics the user typed for their own songs, by track key.
  final Map<String, String> ownLyrics = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    liked.addAll(_readTracks(_kLiked));
    stations.addAll(_readTracks(_kStations));
    localTracks.addAll(_readTracks(_kLocal));
    recent.addAll(_readTracks(_kRecent));
    recentSearches.addAll(_prefs!.getStringList(_kSearches) ?? const []);
    profile = _readJson(_kProfile, Profile.fromJson) ?? Profile(name: 'Listener');
    followedArtists.addAll(_readList(_kArtists, Artist.fromJson));
    savedPlaylists.addAll(_readList(_kSavedPlaylists, Collection.fromJson));
    final lyr = _prefs!.getString(_kLyrics);
    if (lyr != null) {
      try {
        ownLyrics.addAll(Map<String, String>.from(jsonDecode(lyr) as Map));
      } catch (_) {}
    }
    for (final st in _readList(_kStats, PlayStat.fromJson)) {
      stats[st.track.key] = st;
    }
    final raw = _prefs!.getString(_kPlaylists);
    if (raw != null) {
      try {
        playlists.addAll((jsonDecode(raw) as List)
            .map((e) => UserPlaylist.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }
    notifyListeners();
  }

  T? _readJson<T>(String key, T Function(Map<String, dynamic>) parse) {
    final raw = _prefs?.getString(key);
    if (raw == null) return null;
    try {
      return parse(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) parse) {
    final raw = _prefs?.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => parse(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  void _writeList(String key, Iterable<dynamic> items) =>
      _prefs?.setString(key, jsonEncode(items.map((e) => e.toJson()).toList()));

  List<Track> _readTracks(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _writeTracks(String key, List<Track> tracks) =>
      _prefs?.setString(key, jsonEncode(tracks.map((t) => t.toJson()).toList()));

  void _savePlaylists() =>
      _prefs?.setString(_kPlaylists, jsonEncode(playlists.map((p) => p.toJson()).toList()));

  // ---------------------------------------------------------------- likes
  bool isLiked(Track t) =>
      t.isLive ? stations.contains(t) : liked.contains(t);

  /// Songs go to Liked Songs; radio stations go to Saved stations.
  /// Returns the new liked state.
  bool toggleLike(Track t) {
    final list = t.isLive ? stations : liked;
    final now = !list.contains(t);
    if (now) {
      list.insert(0, t);
    } else {
      list.remove(t);
    }
    _writeTracks(t.isLive ? _kStations : _kLiked, list);
    notifyListeners();
    return now;
  }

  // ------------------------------------------------------------ playlists
  UserPlaylist createPlaylist(String name, {List<Track> tracks = const []}) {
    final p = UserPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'My playlist #${playlists.length + 1}' : name.trim(),
      tracks: [...tracks],
      created: DateTime.now(),
    );
    playlists.insert(0, p);
    _savePlaylists();
    notifyListeners();
    return p;
  }

  UserPlaylist? playlistById(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Returns false when the track was already in the playlist.
  bool addToPlaylist(UserPlaylist p, Track t) {
    if (p.tracks.contains(t)) return false;
    p.tracks.add(t);
    _savePlaylists();
    notifyListeners();
    return true;
  }

  void removeFromPlaylist(UserPlaylist p, Track t) {
    p.tracks.remove(t);
    _savePlaylists();
    notifyListeners();
  }

  void reorderPlaylist(UserPlaylist p, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final t = p.tracks.removeAt(oldIndex);
    p.tracks.insert(newIndex, t);
    _savePlaylists();
    notifyListeners();
  }

  /// [to] is the final index (already adjusted for the removed item).
  void movePlaylistTrack(UserPlaylist p, int from, int to) {
    if (from == to) return;
    final t = p.tracks.removeAt(from);
    p.tracks.insert(to.clamp(0, p.tracks.length), t);
    _touch(p);
  }

  void renamePlaylist(UserPlaylist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _savePlaylists();
    notifyListeners();
  }

  void deletePlaylist(UserPlaylist p) {
    playlists.remove(p);
    _deleteImage(p.coverPath);
    _savePlaylists();
    notifyListeners();
  }

  void _touch(UserPlaylist p) {
    p.updated = DateTime.now();
    _savePlaylists();
    notifyListeners();
  }

  void editPlaylist(UserPlaylist p, {String? name, String? description}) {
    if (name != null && name.trim().isNotEmpty) p.name = name.trim();
    if (description != null) p.description = description.trim();
    _touch(p);
  }

  /// Lets the user pick a photo for the playlist cover. Returns false if cancelled.
  Future<bool> pickPlaylistCover(UserPlaylist p, {ImageSource source = ImageSource.gallery}) async {
    final path = await _pickImage('cover_${p.id}', source);
    if (path == null) return false;
    _deleteImage(p.coverPath);
    p.coverPath = path;
    _touch(p);
    return true;
  }

  void removePlaylistCover(UserPlaylist p) {
    _deleteImage(p.coverPath);
    p.coverPath = null;
    _touch(p);
  }

  void togglePin(UserPlaylist p) {
    p.pinned = !p.pinned;
    _touch(p);
  }

  UserPlaylist duplicatePlaylist(UserPlaylist p) {
    final copy = createPlaylist('${p.name} (copy)', tracks: p.tracks);
    copy.description = p.description;
    _savePlaylists();
    return copy;
  }

  /// Adds every track not already in the playlist; returns how many were added.
  int addAllToPlaylist(UserPlaylist p, List<Track> tracks) {
    var n = 0;
    for (final t in tracks) {
      if (!t.isLive && !p.tracks.contains(t)) {
        p.tracks.add(t);
        n++;
      }
    }
    if (n > 0) _touch(p);
    return n;
  }

  // -------------------------------------------------------------- profile
  void setProfileName(String name) {
    if (name.trim().isEmpty) return;
    profile.name = name.trim();
    _prefs?.setString(_kProfile, jsonEncode(profile.toJson()));
    notifyListeners();
  }

  Future<bool> pickAvatar({ImageSource source = ImageSource.gallery}) async {
    final path = await _pickImage('avatar', source);
    if (path == null) return false;
    _deleteImage(profile.avatarPath);
    profile.avatarPath = path;
    _prefs?.setString(_kProfile, jsonEncode(profile.toJson()));
    notifyListeners();
    return true;
  }

  void removeAvatar() {
    _deleteImage(profile.avatarPath);
    profile.avatarPath = null;
    _prefs?.setString(_kProfile, jsonEncode(profile.toJson()));
    notifyListeners();
  }

  /// Copies a picked photo into the app's own folder so it survives
  /// the original being deleted. Returns the new path, or null if cancelled.
  Future<String?> _pickImage(String prefix, ImageSource source) async {
    if (kIsWeb) return null;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 88,
    );
    if (picked == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}mutiny_images');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : 'jpg';
    final dest = File('${dir.path}${Platform.pathSeparator}${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await dest.writeAsBytes(await picked.readAsBytes());
    return dest.path;
  }

  void _deleteImage(String? path) {
    if (path == null || kIsWeb) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ------------------------------------------------- follows & saved lists
  bool isFollowing(Artist a) => followedArtists.contains(a);

  bool toggleFollow(Artist a) {
    final now = !followedArtists.contains(a);
    if (now) {
      followedArtists.insert(0, a);
    } else {
      followedArtists.remove(a);
    }
    _writeList(_kArtists, followedArtists);
    notifyListeners();
    return now;
  }

  bool isPlaylistSaved(Collection c) => savedPlaylists.contains(c);

  bool toggleSavePlaylist(Collection c) {
    final now = !savedPlaylists.contains(c);
    if (now) {
      savedPlaylists.insert(0, c);
    } else {
      savedPlaylists.remove(c);
    }
    _writeList(_kSavedPlaylists, savedPlaylists);
    notifyListeners();
    return now;
  }

  // ---------------------------------------------------------------- stats
  /// Called by the player when a song stops being the current one.
  /// Counts as a play after 30 seconds, like Spotify.
  void recordListen(Track t, int seconds) {
    if (seconds < 5) return;
    final st = stats.putIfAbsent(t.key, () => PlayStat(track: t));
    st.seconds += seconds;
    if (seconds >= 30) st.plays++;
    st.last = DateTime.now();
    if (stats.length > 500) {
      final oldest = stats.values.toList()..sort((a, b) => a.last.compareTo(b.last));
      for (final o in oldest.take(stats.length - 500)) {
        stats.remove(o.track.key);
      }
    }
    _writeList(_kStats, stats.values);
    notifyListeners();
  }

  int get totalListenMinutes => stats.values.fold<int>(0, (s, e) => s + e.seconds) ~/ 60;

  List<PlayStat> topTracks({int limit = 10, Duration? within}) {
    final since = within == null ? null : DateTime.now().subtract(within);
    final list = stats.values
        .where((s) => !s.track.isLive && s.plays > 0 && (since == null || s.last.isAfter(since)))
        .toList()
      ..sort((a, b) => b.plays != a.plays ? b.plays.compareTo(a.plays) : b.seconds.compareTo(a.seconds));
    return list.take(limit).toList();
  }

  /// Artists ranked by listening time: (name, artistId, cover, minutes).
  List<(String, String?, String?, int)> topArtists({int limit = 8}) {
    final byArtist = <String, (String?, String?, int)>{};
    for (final s in stats.values) {
      if (s.track.isLive) continue;
      final prev = byArtist[s.track.artist];
      byArtist[s.track.artist] = (
        prev?.$1 ?? s.track.artistId,
        prev?.$2 ?? s.track.artworkUrl,
        (prev?.$3 ?? 0) + s.seconds,
      );
    }
    final list = byArtist.entries.map((e) => (e.key, e.value.$1, e.value.$2, e.value.$3 ~/ 60)).toList()
      ..sort((a, b) => b.$4.compareTo(a.$4));
    return list.take(limit).toList();
  }

  // -------------------------------------------------------------- history
  void addRecent(Track t) {
    recent.remove(t);
    recent.insert(0, t);
    if (recent.length > 40) recent.removeRange(40, recent.length);
    _writeTracks(_kRecent, recent);
    notifyListeners();
  }

  void addSearch(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    recentSearches.removeWhere((s) => s.toLowerCase() == query.toLowerCase());
    recentSearches.insert(0, query);
    if (recentSearches.length > 12) recentSearches.removeLast();
    _prefs?.setStringList(_kSearches, recentSearches);
    notifyListeners();
  }

  void removeSearch(String q) {
    recentSearches.remove(q);
    _prefs?.setStringList(_kSearches, recentSearches);
    notifyListeners();
  }

  void clearHistory() {
    recent.clear();
    recentSearches.clear();
    _writeTracks(_kRecent, recent);
    _prefs?.setStringList(_kSearches, recentSearches);
    notifyListeners();
  }

  // ---------------------------------------------------------- local files
  /// Lets the user pick audio files and copies them into the app's own
  /// folder, so they keep playing even if the originals move.
  /// Returns how many files were added.
  Future<int> importLocalFiles() async {
    if (kIsWeb) return 0;
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    if (picked.isEmpty) return 0;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}mutiny_music');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    var added = 0;
    for (final f in picked) {
      final safeName = f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dest = File('${dir.path}${Platform.pathSeparator}$safeName');
      try {
        if (!dest.existsSync()) {
          final src = f.path;
          if (src != null && File(src).existsSync()) {
            await File(src).copy(dest.path);
          } else {
            await dest.writeAsBytes(await f.xFile.readAsBytes());
          }
        }
      } catch (_) {
        continue;
      }
      final (artist, title) = parseFileName(f.name);
      final track = Track(
        id: safeName,
        title: title,
        artist: artist,
        source: TrackSource.local,
        uri: dest.path,
        genre: 'On this device',
      );
      if (!localTracks.contains(track)) {
        localTracks.add(track);
        added++;
      }
    }
    localTracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _writeTracks(_kLocal, localTracks);
    notifyListeners();
    return added;
  }

  // ------------------------------------------------------------ own songs
  /// Asks for one audio file and copies it into the app. Returns its new
  /// path and original file name, or null if cancelled.
  Future<(String path, String name)?> pickSongFile() async {
    if (kIsWeb) return null;
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    if (picked.isEmpty) return null;
    final f = picked.first;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}mutiny_music');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safeName = f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dest = File('${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$safeName');
    final src = f.path;
    if (src != null && File(src).existsSync()) {
      await File(src).copy(dest.path);
    } else {
      await dest.writeAsBytes(await f.xFile.readAsBytes());
    }
    return (dest.path, f.name);
  }

  /// Lets the user pick a cover picture for one of their songs.
  Future<String?> pickSongCover({ImageSource source = ImageSource.gallery}) => _pickImage('song', source);

  /// Saves a song the user added themselves. It stays on this device only.
  Track addOwnSong({
    required String audioPath,
    required String title,
    required String artist,
    String? coverPath,
    String lyrics = '',
    int? durationSec,
  }) {
    final t = Track(
      id: 'own_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Untitled' : title.trim(),
      artist: artist.trim().isEmpty ? profile.name : artist.trim(),
      artworkUrl: coverPath,
      artworkLargeUrl: coverPath,
      durationSec: durationSec,
      source: TrackSource.local,
      uri: audioPath,
      genre: 'My songs',
    );
    localTracks.insert(0, t);
    _setLyrics(t, lyrics);
    _writeTracks(_kLocal, localTracks);
    notifyListeners();
    return t;
  }

  /// Changes a song's details; the change shows everywhere it appears
  /// (My songs, Liked Songs, playlists, history).
  Track updateOwnSong(
    Track old, {
    required String title,
    required String artist,
    String? coverPath,
    bool removeCover = false,
    String? lyrics,
  }) {
    final newCover = removeCover ? null : (coverPath ?? old.artworkUrl);
    if (newCover != old.artworkUrl && old.artworkUrl != null && !old.artworkUrl!.startsWith('http')) {
      _deleteImage(old.artworkUrl);
    }
    final t = Track(
      id: old.id,
      title: title.trim().isEmpty ? old.title : title.trim(),
      artist: artist.trim().isEmpty ? old.artist : artist.trim(),
      artworkUrl: newCover,
      artworkLargeUrl: newCover,
      durationSec: old.durationSec,
      source: old.source,
      uri: old.uri,
      genre: old.genre,
    );
    void swap(List<Track> list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] == t) list[i] = t;
      }
    }

    swap(localTracks);
    swap(liked);
    swap(recent);
    for (final p in playlists) {
      swap(p.tracks);
    }
    final st = stats[t.key];
    if (st != null) stats[t.key] = PlayStat(track: t, plays: st.plays, seconds: st.seconds, last: st.last);
    if (lyrics != null) _setLyrics(t, lyrics);
    _writeTracks(_kLocal, localTracks);
    _writeTracks(_kLiked, liked);
    _writeTracks(_kRecent, recent);
    _writeList(_kStats, stats.values);
    _savePlaylists();
    notifyListeners();
    return t;
  }

  String? lyricsFor(Track t) {
    final l = ownLyrics[t.key];
    return (l == null || l.trim().isEmpty) ? null : l;
  }

  void _setLyrics(Track t, String lyrics) {
    if (lyrics.trim().isEmpty) {
      ownLyrics.remove(t.key);
    } else {
      ownLyrics[t.key] = lyrics.trim();
    }
    _prefs?.setString(_kLyrics, jsonEncode(ownLyrics));
  }

  Future<void> removeLocal(Track t) async {
    localTracks.remove(t);
    liked.remove(t);
    if (t.artworkUrl != null && !t.artworkUrl!.startsWith('http')) _deleteImage(t.artworkUrl);
    if (ownLyrics.remove(t.key) != null) _prefs?.setString(_kLyrics, jsonEncode(ownLyrics));
    for (final p in playlists) {
      p.tracks.remove(t);
    }
    try {
      final f = File(t.uri);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    _writeTracks(_kLocal, localTracks);
    _writeTracks(_kLiked, liked);
    _savePlaylists();
    notifyListeners();
  }

  /// "Artist - Title.mp3" → (Artist, Title). Otherwise the whole name is the title.
  static (String, String) parseFileName(String fileName) {
    var base = fileName;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = base.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty) {
      return (parts.first.trim(), parts.sublist(1).join(' - ').trim());
    }
    return ('Unknown artist', base.isEmpty ? fileName : base);
  }
}
