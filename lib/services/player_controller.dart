import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'audius_api.dart';
import 'library_store.dart';

enum RepeatState { off, all, one }

/// Another of the user's devices that this one is controlling (Mutiny
/// Connect). While set, the player shows that device's music and every
/// button sends a command to it instead of playing here.
abstract class RemotePlayer {
  String get name;
  Track? get current;
  bool get playing;
  Duration get position;
  Duration? get duration;
  List<Track> get queue;
  int get queueIndex;
  bool get shuffle;
  RepeatState get repeat;
  String? get contextName;
  Stream<Duration> get positionStream;
  void command(String cmd, [Map<String, dynamic> args = const {}]);
}

/// The playback engine: one queue, shuffle, repeat, sleep timer,
/// lock-screen controls (via just_audio_background on iOS/Android).
class PlayerController extends ChangeNotifier {
  PlayerController(this.library) {
    SharedPreferences.getInstance().then((p) {
      _shuffleOn = p.getBool(_kShuffle) ?? false;
      notifyListeners();
    });
    _subs.add(player.sequenceStateStream.listen(_onSequence));
    _subs.add(player.playerStateStream.listen((_) => notifyListeners()));
    _subs.add(player.errorStream.listen(_onError));
    _subs.add(player.positionStream.listen((p) => _lastPosition = p));
    _watchHeadphones();
  }

  /// Pause when headphones / Bluetooth disconnect, like other music apps.
  Future<void> _watchHeadphones() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      _subs.add(session.becomingNoisyEventStream.listen((_) => player.pause()));
    } catch (_) {}
  }

  final LibraryStore library;
  final AudioPlayer player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];

  /// Set by the UI to show a short message (toast).
  void Function(String message)? onMessage;

  Track? _current;
  Duration _lastPosition = Duration.zero;
  String? _lastRecentKey;
  int _consecutiveErrors = 0;
  String? _contextName;

  // ------------------------------------------------------- remote (Connect)
  RemotePlayer? _remote;

  /// The device being controlled, or null when music plays here.
  RemotePlayer? get remote => _remote;
  set remote(RemotePlayer? r) {
    _remote = r;
    notifyListeners();
  }

  /// Called by Connect when the controlled device reports something new.
  void remoteChanged() => notifyListeners();

  /// Where "Playing from" points (playlist name…).
  String? get contextName => _remote != null ? _remote!.contextName : _contextName;
  set contextName(String? v) => _contextName = v;

  Track? get current => _remote != null ? _remote!.current : _current;
  bool get hasTrack => current != null;
  bool get playing => _remote?.playing ?? player.playing;
  bool get buffering =>
      _remote == null &&
      (player.processingState == ProcessingState.loading || player.processingState == ProcessingState.buffering);

  /// What is playing on this device itself (ignores Connect).
  Track? get localTrack => _current;
  bool get localPlaying => player.playing;
  static const _kShuffle = 'mutiny.shuffle';
  bool _shuffleOn = false;

  /// Shuffle switch, like Spotify's: when on, Play starts the list in a
  /// random order; when off, songs play in order. Remembered across launches.
  bool get shuffle => _remote?.shuffle ?? _shuffleOn;
  RepeatState get repeat => _remote?.repeat ?? localRepeat;
  RepeatState get localRepeat => switch (player.loopMode) {
        LoopMode.off => RepeatState.off,
        LoopMode.all => RepeatState.all,
        LoopMode.one => RepeatState.one,
      };

  Stream<Duration> get positionStream => _remote?.positionStream ?? player.positionStream;
  Duration get position => _remote?.position ?? player.position;
  Duration? get duration => _remote != null ? _remote!.duration : localDuration;
  Duration? get localDuration => player.duration ??
      (_current?.durationSec != null ? Duration(seconds: _current!.durationSec!) : null);

  // ---------------------------------------------------------------- queue
  /// The queue in play order (shuffled order when shuffle is on).
  List<Track> get queue => _remote?.queue ?? localQueue;

  /// This device's own queue.
  List<Track> get localQueue => player.sequenceState.effectiveSequence
      .map((s) => trackOf(s.tag))
      .whereType<Track>()
      .toList();

  /// Position of the current track inside [queue].
  ///
  /// Shuffle is done by Mutiny itself (the queue really is put in random
  /// order) instead of the audio engine's shuffle mode: on Windows the
  /// engine shuffled its own copy of the list, so skipping went out of step
  /// and songs played in order. Queue position = engine index, always.
  int get queueIndex => _remote?.queueIndex ?? localQueueIndex;
  int get localQueueIndex => player.sequenceState.currentIndex ?? 0;

  int _sequenceIndexFor(int queuePos) => queuePos;

  /// The list in its own order (what Shuffle off goes back to).
  List<Track> _original = [];

  static Track? trackOf(Object? tag) {
    if (tag is MediaItem) {
      final raw = tag.extras?['track'];
      if (raw is String) {
        try {
          return Track.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        } catch (_) {}
      }
    }
    return null;
  }

  static AudioSource sourceFor(Track t) {
    final art = t.bestArtwork;
    final tag = MediaItem(
      id: t.key,
      title: t.title,
      artist: t.artist,
      album: t.isLive ? 'Live radio' : (t.genre ?? 'Mutiny'),
      artUri: art == null ? null : (art.startsWith('http') ? Uri.tryParse(art) : Uri.file(art)),
      duration: t.durationSec == null ? null : Duration(seconds: t.durationSec!),
      extras: {'track': jsonEncode(t.toJson())},
    );
    if (t.isLocal) return AudioSource.file(t.uri, tag: tag);
    return AudioSource.uri(Uri.parse(t.uri), tag: tag);
  }

  /// Replace the queue and start playing.
  ///
  /// [index]: the song the user tapped (plays first, also when shuffling).
  /// Without it, the list starts at the top, or anywhere when shuffle is on.
  /// [shuffled] overrides the shuffle switch for this list only.
  Future<void> playTracks(
    List<Track> tracks, {
    int? index,
    bool? shuffled,
    String? from,
  }) async {
    if (tracks.isEmpty) return;
    if (_remote != null) {
      _remote!.command('playTracks', {
        'tracks': [for (final t in tracks.take(300)) t.toJson()],
        'index': index,
        'shuffled': shuffled,
        'from': from,
      });
      return;
    }
    return _playTracksLocal(tracks, index: index, shuffled: shuffled, from: from);
  }

  Future<void> _playTracksLocal(
    List<Track> tracks, {
    int? index,
    bool? shuffled,
    String? from,
  }) async {
    if (tracks.isEmpty) return;
    _contextName = from;
    _consecutiveErrors = 0;
    final shuffleThis = (shuffled ?? _shuffleOn) && tracks.length > 1;
    _original = List.of(tracks);
    final order = shuffleOrder(tracks, first: index, shuffle: shuffleThis);
    final start = shuffleThis ? 0 : (index ?? 0).clamp(0, tracks.length - 1);
    try {
      if (player.shuffleModeEnabled) await player.setShuffleModeEnabled(false);
      // A single radio station should never repeat-loop a whole queue.
      if (tracks.length == 1 && tracks.first.isLive && player.loopMode == LoopMode.one) {
        await player.setLoopMode(LoopMode.off);
      }
      final load = player.setAudioSources(
        order.map(sourceFor).toList(),
        initialIndex: start,
        preload: false,
      );
      unawaited(player.play());
      await load;
    } on PlayerInterruptedException {
      // A newer play request replaced this one.
    } catch (e) {
      onMessage?.call("Couldn't play that right now");
    }
  }

  Future<void> playTrack(Track t, {String? from}) {
    if (t.source == TrackSource.radio) {
      // A radio station counts as something to jump back into, like a playlist.
      library.markPlayedFrom(PlayContext(
        type: PlayContextType.station,
        id: t.id,
        title: t.title,
        subtitle: 'Radio',
        artworkUrl: t.artworkUrl,
        data: t.toJson(),
      ));
    }
    return playTracks([t], from: from);
  }

  /// Spotify-style song radio: this song, then similar music
  /// (same artist + trending in the same genre), shuffled.
  Future<void> startSongRadio(Track seed) async {
    onMessage?.call('Starting “${seed.title}” radio…');
    final api = AudiusApi();
    final results = await Future.wait([
      if (seed.artistId != null) api.artistTracks(seed.artistId!).catchError((_) => <Track>[]),
      api.trending(genre: seed.genre, limit: 40).catchError((_) => <Track>[]),
    ]);
    final seen = <String>{seed.key};
    final mix = [for (final l in results) ...l].where((t) => seen.add(t.key)).toList()..shuffle();
    if (mix.isEmpty) {
      onMessage?.call("Couldn't find similar songs");
      return;
    }
    await playTracks([seed, ...mix.take(60)], index: 0, shuffled: false, from: '${seed.title} radio');
  }

  Future<void> addToQueue(Track t) async {
    if (_remote != null) {
      _remote!.command('add', {'track': t.toJson()});
      onMessage?.call('Added to queue on ${_remote!.name}');
      return;
    }
    return _addToQueueLocal(t);
  }

  Future<void> _addToQueueLocal(Track t) async {
    if (_current == null) return _playTracksLocal([t]);
    _original.add(t);
    await player.addAudioSource(sourceFor(t));
    onMessage?.call('Added to queue');
    notifyListeners();
  }

  Future<void> playNext(Track t) async {
    if (_remote != null) {
      _remote!.command('playNext', {'track': t.toJson()});
      onMessage?.call('Plays next on ${_remote!.name}');
      return;
    }
    return _playNextLocal(t);
  }

  Future<void> _playNextLocal(Track t) async {
    if (_current == null) return _playTracksLocal([t]);
    final i = player.currentIndex ?? -1;
    final cur = _current == null ? -1 : _original.indexOf(_current!);
    _original.insert(cur + 1, t);
    await player.insertAudioSource(i + 1, sourceFor(t));
    onMessage?.call('Plays next');
    notifyListeners();
  }

  Future<void> removeFromQueue(int queuePos) async {
    if (_remote != null) return _remote!.command('remove', {'i': queuePos});
    return _removeLocal(queuePos);
  }

  Future<void> _removeLocal(int queuePos) async {
    if (queuePos == localQueueIndex) return;
    await player.removeAudioSourceAt(_sequenceIndexFor(queuePos));
    notifyListeners();
  }

  /// The queue can always be reordered (shuffle is a real order now).
  bool get canReorder => true;

  /// [to] is the final index (already adjusted for the removed item).
  Future<void> moveInQueue(int from, int to) async {
    if (_remote != null) return _remote!.command('move', {'from': from, 'to': to});
    return _moveLocal(from, to);
  }

  Future<void> _moveLocal(int from, int to) async {
    if (!canReorder || from == to) return;
    await player.moveAudioSource(from, to);
    notifyListeners();
  }

  Future<void> jumpTo(int queuePos) async {
    if (_remote != null) return _remote!.command('jump', {'i': queuePos});
    return _jumpLocal(queuePos);
  }

  Future<void> _jumpLocal(int queuePos) async {
    await player.seek(Duration.zero, index: _sequenceIndexFor(queuePos));
    if (!player.playing) unawaited(player.play());
  }

  // ------------------------------------------------------------- transport
  Future<void> togglePlay() async {
    if (_remote != null) return _remote!.command(_remote!.playing ? 'pause' : 'play');
    return _toggleLocal();
  }

  Future<void> _toggleLocal() async {
    if (_current == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: player.currentIndex);
      }
      unawaited(player.play());
    }
  }

  Future<void> next() async {
    if (_remote != null) return _remote!.command('next');
    return _nextLocal();
  }

  Future<void> _nextLocal() async {
    if (player.hasNext) {
      await player.seekToNext();
    } else if (player.loopMode == LoopMode.off) {
      await player.pause();
      await player.seek(Duration.zero);
    }
  }

  Future<void> previous() async {
    if (_remote != null) return _remote!.command('previous');
    return _previousLocal();
  }

  Future<void> _previousLocal() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration d) async {
    if (_remote != null) return _remote!.command('seek', {'ms': d.inMilliseconds});
    return player.seek(d);
  }

  Future<void> toggleShuffle() => setShuffle(!shuffle);

  /// [tracks] in play order: unchanged, or [first] (or a random song) first
  /// and every other song after it in random order.
  static List<Track> shuffleOrder(List<Track> tracks, {int? first, required bool shuffle, math.Random? random}) {
    if (!shuffle || tracks.length < 2) return List.of(tracks);
    final rnd = random ?? math.Random();
    final f = (first ?? rnd.nextInt(tracks.length)).clamp(0, tracks.length - 1);
    final rest = [...tracks]..removeAt(f);
    rest.shuffle(rnd);
    return [tracks[f], ...rest];
  }

  /// The queue around the current song when the switch changes: shuffle on
  /// → every other song in random order after it; off → the list's own
  /// order again, continuing after the current song.
  static ({List<Track> before, List<Track> after}) reorderAround(
    List<Track> queue,
    int current,
    List<Track> original, {
    required bool shuffle,
    math.Random? random,
  }) {
    final cur = queue[current];
    if (shuffle) {
      final others = [...queue]..removeAt(current);
      others.shuffle(random ?? math.Random());
      return (before: const [], after: others);
    }
    // Original order, plus anything added later that it doesn't know.
    final pool = [...queue]..removeAt(current);
    final ordered = <Track>[];
    for (final t in original) {
      if (pool.remove(t)) ordered.add(t);
    }
    ordered.addAll(pool);
    // The current song's place in the original list decides what comes next.
    final at = original.indexOf(cur);
    var split = 0;
    if (at >= 0) {
      final before = original.sublist(0, at).toSet();
      split = ordered.takeWhile(before.contains).length;
    }
    return (before: ordered.sublist(0, split), after: ordered.sublist(split));
  }

  /// Turns the shuffle switch on/off; the current queue follows it at once,
  /// without interrupting the song that is playing.
  Future<void> setShuffle(bool on) async {
    if (_remote != null) return _remote!.command('shuffle', {'on': on});
    return _setShuffleLocal(on);
  }

  Future<void> _setShuffleLocal(bool on) async {
    _shuffleOn = on;
    notifyListeners();
    unawaited(SharedPreferences.getInstance().then((p) => p.setBool(_kShuffle, on)));
    final q = localQueue;
    final i = player.currentIndex;
    if (q.length < 2 || i == null || i >= q.length) return;
    final r = reorderAround(q, i, _original, shuffle: on);
    try {
      if (player.shuffleModeEnabled) await player.setShuffleModeEnabled(false);
      final len = player.audioSources.length;
      // Keep the current song loaded; swap everything around it.
      if (i + 1 < len) await player.removeAudioSourceRange(i + 1, len);
      if (i > 0) await player.removeAudioSourceRange(0, i);
      if (r.after.isNotEmpty) await player.addAudioSources(r.after.map(sourceFor).toList());
      if (r.before.isNotEmpty) await player.insertAudioSources(0, r.before.map(sourceFor).toList());
    } catch (e) {
      debugPrint('Shuffle reorder failed: $e');
    }
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    if (_remote != null) return _remote!.command('repeat');
    return _cycleRepeatLocal();
  }

  Future<void> _cycleRepeatLocal() async {
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    notifyListeners();
  }

  // -------------------------------------------------- Connect (this device)
  /// What this device is playing, for the user's other devices.
  Map<String, dynamic> localState() {
    final q = localQueue;
    final i = localQueueIndex;
    // Send a window of the queue around the current song (keeps it small).
    final start = (i - 20).clamp(0, q.isEmpty ? 0 : q.length - 1);
    final end = (i + 80).clamp(0, q.length);
    return {
      'track': _current?.toJson(),
      'playing': player.playing,
      'positionMs': player.position.inMilliseconds,
      'durationMs': localDuration?.inMilliseconds,
      'queue': [for (final t in q.sublist(start, end)) t.toJson()],
      'index': i - start,
      'shuffle': _shuffleOn,
      'repeat': localRepeat.name,
      'from': _contextName,
    };
  }

  /// Own songs live at a different path on each device: use this device's copy.
  Track? _resolve(Object? json) {
    if (json is! Map) return null;
    final t = Track.fromJson(Map<String, dynamic>.from(json));
    if (!t.isLocal) return t;
    for (final mine in library.localTracks) {
      if (mine.id == t.id) return mine;
    }
    return null; // that song's file isn't on this device (yet)
  }

  List<Track> _resolveAll(Object? list) => [
        if (list is List)
          for (final j in list) ?_resolve(j),
      ];

  /// Runs a command sent by another of the user's devices.
  Future<void> handleRemoteCommand(String cmd, Map<String, dynamic> a) async {
    int i(String k) => (a[k] as num?)?.toInt() ?? 0;
    switch (cmd) {
      case 'play':
        if (_current != null && !player.playing) await _toggleLocal();
      case 'pause':
        if (player.playing) await player.pause();
      case 'next':
        await _nextLocal();
      case 'previous':
        await _previousLocal();
      case 'seek':
        await player.seek(Duration(milliseconds: i('ms')));
      case 'jump':
        await _jumpLocal(i('i'));
      case 'remove':
        await _removeLocal(i('i'));
      case 'move':
        await _moveLocal(i('from'), i('to'));
      case 'shuffle':
        await _setShuffleLocal(a['on'] == true);
      case 'repeat':
        await _cycleRepeatLocal();
      case 'add':
        if (_resolve(a['track']) case final t?) await _addToQueueLocal(t);
      case 'playNext':
        if (_resolve(a['track']) case final t?) await _playNextLocal(t);
      case 'playTracks':
        final tracks = _resolveAll(a['tracks']);
        if (tracks.isEmpty) return;
        final idx = (a['index'] as num?)?.toInt();
        await _playTracksLocal(tracks, index: idx?.clamp(0, tracks.length - 1), shuffled: a['shuffled'] as bool?, from: a['from'] as String?);
      case 'transfer':
        // Another device hands its music over: continue right where it was.
        final tracks = _resolveAll(a['queue']);
        if (tracks.isEmpty) return;
        final idx = i('index').clamp(0, tracks.length - 1);
        await _playTracksLocal(tracks, index: idx, shuffled: false, from: a['from'] as String?);
        _shuffleOn = a['shuffle'] == true;
        await player.seek(Duration(milliseconds: i('positionMs')), index: idx);
        if (a['playing'] == false) await player.pause();
        notifyListeners();
    }
  }

  // ----------------------------------------------------------- sleep timer
  Timer? _sleepTimer;
  DateTime? sleepAt;
  bool sleepAfterTrack = false;

  bool get sleepActive => sleepAt != null || sleepAfterTrack;

  void setSleepTimer(Duration? d, {bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    sleepAfterTrack = endOfTrack;
    if (d != null) {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () {
        player.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- internals
  void _onSequence(SequenceState st) {
    final prevKey = _current?.key;
    final prev = _current;
    _current = trackOf(st.currentSource?.tag);
    final key = _current?.key;
    if (key != prevKey && prev != null) {
      // Remember how long the previous song was listened to (profile stats).
      var secs = _lastPosition.inSeconds;
      if (prev.durationSec != null && secs > prev.durationSec!) secs = prev.durationSec!;
      library.recordListen(prev, secs);
      _lastPosition = Duration.zero;
    }
    if (key != null && key != prevKey) {
      if (sleepAfterTrack && prevKey != null) {
        sleepAfterTrack = false;
        player.pause();
      }
      if (key != _lastRecentKey) {
        _lastRecentKey = key;
        library.addRecent(_current!);
      }
      _consecutiveErrors = 0;
    }
    notifyListeners();
  }

  void _onError(PlayerException e) {
    _consecutiveErrors++;
    final name = _current?.title;
    if (_consecutiveErrors > 3 || !player.hasNext) {
      onMessage?.call(name == null ? "Couldn't play this" : "Couldn't play “$name”");
      player.pause();
      return;
    }
    onMessage?.call(name == null ? 'Skipped an unavailable track' : 'Skipped “$name” (unavailable)');
    player.seekToNext().then((_) => player.play());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _sleepTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}
