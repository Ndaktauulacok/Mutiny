import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

  SharedPreferences? _prefs;

  final List<Track> liked = [];
  final List<UserPlaylist> playlists = [];
  final List<Track> stations = [];
  final List<Track> localTracks = [];
  final List<Track> recent = [];
  final List<String> recentSearches = [];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    liked.addAll(_readTracks(_kLiked));
    stations.addAll(_readTracks(_kStations));
    localTracks.addAll(_readTracks(_kLocal));
    recent.addAll(_readTracks(_kRecent));
    recentSearches.addAll(_prefs!.getStringList(_kSearches) ?? const []);
    final raw = _prefs!.getString(_kPlaylists);
    if (raw != null) {
      try {
        playlists.addAll((jsonDecode(raw) as List)
            .map((e) => UserPlaylist.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }
    notifyListeners();
  }

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

  void renamePlaylist(UserPlaylist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _savePlaylists();
    notifyListeners();
  }

  void deletePlaylist(UserPlaylist p) {
    playlists.remove(p);
    _savePlaylists();
    notifyListeners();
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

  Future<void> removeLocal(Track t) async {
    localTracks.remove(t);
    liked.remove(t);
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
