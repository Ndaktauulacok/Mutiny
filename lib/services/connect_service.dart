import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'cloud_sync.dart';
import 'player_controller.dart';

/// One of the user's other devices that is online.
class ConnectDevice {
  ConnectDevice({required this.id, required this.name, required this.platform});
  final String id;
  String name;
  String platform;

  /// Last thing it reported playing (null until it says).
  RemoteState? state;

  String get icon => platform;
}

/// What another device reported playing, with the time it arrived so the
/// position can keep moving between reports.
class RemoteState {
  RemoteState({
    required this.track,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.queue,
    required this.index,
    required this.shuffle,
    required this.repeat,
    required this.from,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  final Track? track;
  final bool playing;
  final int positionMs;
  final int? durationMs;
  final List<Track> queue;
  final int index;
  final bool shuffle;
  final RepeatState repeat;
  final String? from;
  final DateTime receivedAt;

  /// Estimated position now (keeps running while it plays).
  Duration positionAt(DateTime now) {
    var ms = positionMs + (playing ? now.difference(receivedAt).inMilliseconds : 0);
    if (durationMs != null && durationMs! > 0) ms = math.min(ms, durationMs!);
    return Duration(milliseconds: math.max(0, ms));
  }

  static RemoteState fromJson(Map<String, dynamic> j) {
    Track? track(Object? o) => o is Map ? Track.fromJson(Map<String, dynamic>.from(o)) : null;
    return RemoteState(
      track: track(j['track']),
      playing: j['playing'] == true,
      positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (j['durationMs'] as num?)?.toInt(),
      queue: [
        for (final q in (j['queue'] as List? ?? const [])) ?track(q),
      ],
      index: (j['index'] as num?)?.toInt() ?? 0,
      shuffle: j['shuffle'] == true,
      repeat: RepeatState.values.where((r) => r.name == j['repeat']).firstOrNull ?? RepeatState.off,
      from: j['from'] as String?,
    );
  }
}

/// Mutiny Connect: the user's devices that are signed in to the same account
/// see each other, and one can play music on another, like Spotify Connect.
/// E.g. music plays on the laptop and the phone is the remote.
///
/// Each device plays on its own unless the user picks another device in
/// "Play on". Devices talk over a private Supabase Realtime channel only the
/// user's own devices can join (`connect:<user id>`).
class ConnectService extends ChangeNotifier implements RemotePlayer {
  ConnectService({required this.player, required this.cloud});

  final PlayerController player;
  final CloudSync cloud;

  static const _kDeviceId = 'mutiny.connect.device';

  late String deviceId;
  late String deviceName;
  late String platform;

  final Map<String, ConnectDevice> _devices = {};
  RealtimeChannel? _channel;
  String? _uid;
  String? _targetId;
  Timer? _heartbeat;
  Timer? _debounce;
  Timer? _tick;
  final _position = StreamController<Duration>.broadcast();
  Map<String, dynamic>? _lastSent;

  /// Other devices online right now.
  List<ConnectDevice> get devices => _devices.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// The device being controlled, or null when music plays on this one.
  ConnectDevice? get target => _targetId == null ? null : _devices[_targetId];

  bool get online => _channel != null;

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString(_kDeviceId) ?? _newId();
    await prefs.setString(_kDeviceId, deviceId);
    final (n, pl) = _describeThisDevice();
    deviceName = n;
    platform = pl;
    cloud.addListener(_onCloud);
    player.addListener(_onPlayer);
    _onCloud();
  }

  static String _newId() {
    final r = math.Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  static (String, String) _describeThisDevice() {
    if (kIsWeb) return ('Web browser', 'web');
    if (Platform.isIOS) return ('iPhone', 'ios');
    if (Platform.isAndroid) return ('Android phone', 'android');
    if (Platform.isWindows) {
      final host = Platform.localHostname;
      return (host.isEmpty ? 'Windows PC' : _pretty(host), 'windows');
    }
    if (Platform.isMacOS) return ('Mac', 'mac');
    return ('Computer', 'desktop');
  }

  /// "LAPTOP-LEGION" → "Laptop Legion".
  static String _pretty(String host) => host
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  // ------------------------------------------------------------ connection
  void _onCloud() {
    final uid = cloud.user?.id;
    if (uid == _uid) return;
    _leave();
    _uid = uid;
    if (uid != null && cloud.client != null) _join(cloud.client!, uid);
  }

  void _join(SupabaseClient client, String uid) {
    final ch = client.channel(
      'connect:$uid',
      opts: RealtimeChannelConfig(private: true, key: deviceId),
    );
    ch
        .onPresenceSync((_) => _readPresence())
        .onPresenceJoin((_) => _readPresence())
        .onPresenceLeave((_) => _readPresence())
        .onBroadcast(event: 'state', callback: _onState)
        .onBroadcast(event: 'cmd', callback: _onCommand)
        .onBroadcast(event: 'hello', callback: (_) => _sendState(force: true))
        .subscribe((status, err) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({'id': deviceId, 'name': deviceName, 'platform': platform});
        // Ask the others what they're playing.
        await ch.sendBroadcastMessage(event: 'hello', payload: {'from': deviceId});
        _sendState(force: true);
      }
      if (err != null) debugPrint('Connect: $status $err');
    });
    _channel = ch;
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.localPlaying) _sendState(force: true);
    });
    notifyListeners();
  }

  void _leave() {
    _heartbeat?.cancel();
    _tick?.cancel();
    if (_channel != null) {
      unawaited(cloud.client?.removeChannel(_channel!));
      _channel = null;
    }
    _devices.clear();
    if (_targetId != null) {
      _targetId = null;
      player.remote = null;
    }
    notifyListeners();
  }

  void _readPresence() {
    final ch = _channel;
    if (ch == null) return;
    final seen = <String>{};
    for (final p in ch.presenceState()) {
      for (final pr in p.presences) {
        final id = pr.payload['id'] as String?;
        if (id == null || id == deviceId) continue;
        seen.add(id);
        final d = _devices.putIfAbsent(
          id,
          () => ConnectDevice(id: id, name: pr.payload['name'] as String? ?? 'Device', platform: pr.payload['platform'] as String? ?? ''),
        );
        d.name = pr.payload['name'] as String? ?? d.name;
        d.platform = pr.payload['platform'] as String? ?? d.platform;
      }
    }
    _devices.removeWhere((id, _) => !seen.contains(id));
    // The device we were controlling went offline: play here again.
    if (_targetId != null && !_devices.containsKey(_targetId)) {
      _targetId = null;
      player.remote = null;
      player.onMessage?.call('The other device went offline');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- messages
  void _onState(Map<String, dynamic> msg) {
    final from = msg['from'] as String?;
    final state = msg['state'];
    if (from == null || from == deviceId || state is! Map) return;
    final d = _devices[from];
    if (d == null) return;
    d.state = RemoteState.fromJson(Map<String, dynamic>.from(state));
    notifyListeners();
    if (from == _targetId) player.remoteChanged();
  }

  void _onCommand(Map<String, dynamic> msg) {
    if (msg['to'] != deviceId) return;
    final cmd = msg['cmd'] as String?;
    if (cmd == null) return;
    final args = Map<String, dynamic>.from((msg['args'] as Map?) ?? const {});
    unawaited(player.handleRemoteCommand(cmd, args).then((_) => _sendState(force: true)));
  }

  /// Tells the other devices what plays here (after changes, and every few
  /// seconds while playing).
  void _onPlayer() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _sendState());
  }

  void _sendState({bool force = false}) {
    final ch = _channel;
    if (ch == null) return;
    final state = player.localState();
    // Skip identical reports (position aside).
    final key = {...state}..remove('positionMs');
    if (!force && _lastSent != null && mapEquals(_lastSent, key)) return;
    _lastSent = key;
    unawaited(ch.sendBroadcastMessage(event: 'state', payload: {'from': deviceId, 'state': state}));
  }

  // ---------------------------------------------------------- choosing
  /// Plays on [device] (null = this device). Music that is playing here
  /// moves over and continues where it was, like Spotify Connect.
  Future<void> playOn(ConnectDevice? device) async {
    if (device?.id == _targetId) return;
    if (device == null) {
      // Take the music back to this device.
      final s = target?.state;
      final old = _targetId;
      _targetId = null;
      _tick?.cancel();
      player.remote = null;
      if (s?.track != null && s!.playing) {
        await player.handleRemoteCommand('transfer', {
          'queue': [for (final t in s.queue) t.toJson()],
          'index': s.index,
          'positionMs': s.positionAt(DateTime.now()).inMilliseconds,
          'playing': true,
          'from': s.from,
          'shuffle': s.shuffle,
        });
        _send(old, 'pause');
      }
      notifyListeners();
      return;
    }
    final wasPlaying = player.localTrack != null && player.localPlaying;
    if (wasPlaying) {
      // Hand over what plays here.
      final st = player.localState();
      _send(device.id, 'transfer', {
        'queue': st['queue'],
        'index': st['index'],
        'positionMs': st['positionMs'],
        'playing': true,
        'from': st['from'],
        'shuffle': st['shuffle'],
      });
      await player.player.pause();
    }
    _targetId = device.id;
    player.remote = this;
    // Keep the shown position moving smoothly.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (target?.state?.playing ?? false) _position.add(position);
    });
    notifyListeners();
  }

  void _send(String? to, String cmd, [Map<String, dynamic> args = const {}]) {
    final ch = _channel;
    if (ch == null || to == null) return;
    unawaited(ch.sendBroadcastMessage(event: 'cmd', payload: {'to': to, 'from': deviceId, 'cmd': cmd, 'args': args}));
  }

  // ------------------------------------------- RemotePlayer (the target)
  RemoteState? get _s => target?.state;

  @override
  String get name => target?.name ?? 'another device';
  @override
  Track? get current => _s?.track;
  @override
  bool get playing => _s?.playing ?? false;
  @override
  Duration get position => _s?.positionAt(DateTime.now()) ?? Duration.zero;
  @override
  Duration? get duration => _s?.durationMs == null ? null : Duration(milliseconds: _s!.durationMs!);
  @override
  List<Track> get queue => _s?.queue ?? const [];
  @override
  int get queueIndex => _s?.index ?? 0;
  @override
  bool get shuffle => _s?.shuffle ?? false;
  @override
  RepeatState get repeat => _s?.repeat ?? RepeatState.off;
  @override
  String? get contextName => _s?.from;
  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  void command(String cmd, [Map<String, dynamic> args = const {}]) {
    final s = _s;
    // Show the change at once; the device confirms a moment later.
    if (s != null && (cmd == 'play' || cmd == 'pause')) {
      target!.state = RemoteState(
        track: s.track,
        playing: cmd == 'play',
        positionMs: s.positionAt(DateTime.now()).inMilliseconds,
        durationMs: s.durationMs,
        queue: s.queue,
        index: s.index,
        shuffle: s.shuffle,
        repeat: s.repeat,
        from: s.from,
      );
      player.remoteChanged();
    }
    _send(_targetId, cmd, args);
  }

  @override
  void dispose() {
    _leave();
    _debounce?.cancel();
    cloud.removeListener(_onCloud);
    player.removeListener(_onPlayer);
    _position.close();
    super.dispose();
  }
}
