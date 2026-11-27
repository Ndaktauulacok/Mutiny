import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/models.dart';
import 'audius_api.dart';
import 'library_store.dart';

enum RepeatState { off, all, one }

/// The playback engine: one queue, shuffle, repeat, sleep timer,
/// lock-screen controls (via just_audio_background on iOS/Android).
class PlayerController extends ChangeNotifier {
  PlayerController(this.library) {
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
  String? contextName;

  Track? get current => _current;
  bool get hasTrack => _current != null;
  bool get playing => player.playing;
  bool get buffering =>
      player.processingState == ProcessingState.loading ||
      player.processingState == ProcessingState.buffering;
  bool get shuffle => player.shuffleModeEnabled;
  RepeatState get repeat => switch (player.loopMode) {
        LoopMode.off => RepeatState.off,
        LoopMode.all => RepeatState.all,
        LoopMode.one => RepeatState.one,
      };

  Stream<Duration> get positionStream => player.positionStream;
  Duration get position => player.position;
  Duration? get duration => player.duration ??
      (_current?.durationSec != null ? Duration(seconds: _current!.durationSec!) : null);

  // ---------------------------------------------------------------- queue
  /// The queue in play order (shuffled order when shuffle is on).
  List<Track> get queue => player.sequenceState.effectiveSequence
      .map((s) => trackOf(s.tag))
      .whereType<Track>()
      .toList();

  /// Position of the current track inside [queue].
  int get queueIndex {
    final st = player.sequenceState;
    final i = st.currentIndex;
    if (i == null) return 0;
    if (!st.shuffleModeEnabled) return i;
    final pos = st.shuffleIndices.indexOf(i);
    return pos < 0 ? 0 : pos;
  }

  int _sequenceIndexFor(int queuePos) {
    final st = player.sequenceState;
    return st.shuffleModeEnabled ? st.shuffleIndices[queuePos] : queuePos;
  }

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
  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffled = false,
    String? from,
  }) async {
    if (tracks.isEmpty) return;
    contextName = from;
    _consecutiveErrors = 0;
    final start = shuffled ? (DateTime.now().microsecond % tracks.length) : index;
    try {
      await player.setShuffleModeEnabled(false);
      // A single radio station should never repeat-loop a whole queue.
      if (tracks.length == 1 && tracks.first.isLive && player.loopMode == LoopMode.one) {
        await player.setLoopMode(LoopMode.off);
      }
      final load = player.setAudioSources(
        tracks.map(sourceFor).toList(),
        initialIndex: start.clamp(0, tracks.length - 1),
        preload: false,
      );
      if (shuffled) {
        await load;
        await player.setShuffleModeEnabled(true);
        await player.shuffle();
      }
      unawaited(player.play());
      await load;
    } on PlayerInterruptedException {
      // A newer play request replaced this one.
    } catch (e) {
      onMessage?.call("Couldn't play that right now");
    }
  }

  Future<void> playTrack(Track t, {String? from}) => playTracks([t], from: from);

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
    await playTracks([seed, ...mix.take(60)], from: '${seed.title} radio');
  }

  Future<void> addToQueue(Track t) async {
    if (!hasTrack) return playTrack(t);
    await player.addAudioSource(sourceFor(t));
    onMessage?.call('Added to queue');
    notifyListeners();
  }

  Future<void> playNext(Track t) async {
    if (!hasTrack) return playTrack(t);
    final i = player.currentIndex ?? -1;
    await player.insertAudioSource(i + 1, sourceFor(t));
    onMessage?.call('Plays next');
    notifyListeners();
  }

  Future<void> removeFromQueue(int queuePos) async {
    if (queuePos == queueIndex) return;
    await player.removeAudioSourceAt(_sequenceIndexFor(queuePos));
    notifyListeners();
  }

  /// Reordering only makes sense in normal order.
  bool get canReorder => !shuffle;

  /// [to] is the final index (already adjusted for the removed item).
  Future<void> moveInQueue(int from, int to) async {
    if (!canReorder || from == to) return;
    await player.moveAudioSource(from, to);
    notifyListeners();
  }

  Future<void> jumpTo(int queuePos) async {
    await player.seek(Duration.zero, index: _sequenceIndexFor(queuePos));
    if (!player.playing) unawaited(player.play());
  }

  // ------------------------------------------------------------- transport
  Future<void> togglePlay() async {
    if (!hasTrack) return;
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
    if (player.hasNext) {
      await player.seekToNext();
    } else if (player.loopMode == LoopMode.off) {
      await player.pause();
      await player.seek(Duration.zero);
    }
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration d) => player.seek(d);

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    notifyListeners();
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
