import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'library_store.dart';
import 'sync_merge.dart';

/// Mutiny's cloud: https://rtlycngyhzoqdvnqkbrl.supabase.co (Supabase).
/// The publishable key is meant to ship inside apps; row-level security
/// lets each account read and write only its own rows and files.
abstract final class CloudConfig {
  static const url = 'https://rtlycngyhzoqdvnqkbrl.supabase.co';
  static const publishableKey = 'sb_publishable_2VOZX1niQYLC3q2mtefCcQ_soJFbTLx';
  static const table = 'library_items';
  static const bucket = 'user-files';
  static const maxFileBytes = 50 * 1024 * 1024;
}

enum SyncStatus { signedOut, syncing, synced, offline }

/// One account on every device: signs in, then keeps the library in sync
/// both ways (merge on sign-in, push local changes, live updates).
class CloudSync extends ChangeNotifier {
  CloudSync(this.library);

  final LibraryStore library;

  SupabaseClient? _client;
  SharedPreferences? _prefs;
  String? _docs;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  Timer? _debounce;
  Timer? _retry;
  Future<void> _queue = Future.value();
  bool _applying = false;
  bool _started = false;

  /// key → hash of the item at the last successful sync (per account).
  Map<String, String> _synced = {};

  /// this device's file path → path in cloud storage.
  Map<String, String> _files = {};

  SyncStatus status = SyncStatus.signedOut;
  DateTime? lastSync;
  String? error;
  int pendingDownloads = 0;

  User? get user => _client?.auth.currentUser;
  bool get signedIn => user != null;
  String? get email => user?.email;

  // ---------------------------------------------------------------- setup
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    if (!kIsWeb) _docs = (await getApplicationDocumentsDirectory()).path;
    try {
      await Supabase.initialize(url: CloudConfig.url, publishableKey: CloudConfig.publishableKey);
      _client = Supabase.instance.client;
    } catch (e) {
      debugPrint('Cloud unavailable: $e');
      return;
    }
    _authSub = _client!.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) _stop();
      if (s.session != null && !_started) unawaited(_start());
      notifyListeners();
    });
    if (signedIn) unawaited(_start());
  }

  // ----------------------------------------------------------------- auth
  /// Returns null when signed in, or a message (e.g. "check your email").
  Future<String?> signUp({required String email, required String password, required String name}) async {
    final c = _client;
    if (c == null) return 'Cloud is unavailable right now';
    try {
      final res = await c.auth.signUp(email: email.trim(), password: password, data: {'name': name.trim()});
      if (name.trim().isNotEmpty) library.setProfileName(name);
      if (res.session == null) {
        return 'Almost done! We sent a link to ${email.trim()}. Open it, then sign in here.';
      }
      return null;
    } on AuthException catch (e) {
      return _friendly(e.message);
    } catch (_) {
      return "Couldn't reach the server. Check your internet.";
    }
  }

  Future<String?> signIn({required String email, required String password}) async {
    final c = _client;
    if (c == null) return 'Cloud is unavailable right now';
    try {
      await c.auth.signInWithPassword(email: email.trim(), password: password);
      return null;
    } on AuthException catch (e) {
      return _friendly(e.message);
    } catch (_) {
      return "Couldn't reach the server. Check your internet.";
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await _client?.auth.resetPasswordForEmail(email.trim());
      return 'If that email has an account, a reset link is on its way.';
    } on AuthException catch (e) {
      return _friendly(e.message);
    } catch (_) {
      return "Couldn't reach the server. Check your internet.";
    }
  }

  Future<void> signOut() async {
    await _flush();
    await _client?.auth.signOut();
    _stop();
    notifyListeners();
  }

  static String _friendly(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return 'Wrong email or password.';
    if (s.contains('already registered')) return 'This email already has an account. Sign in instead.';
    if (s.contains('not confirmed')) return 'Please open the link we emailed you first, then sign in.';
    if (s.contains('password')) return 'Password must be at least 6 characters.';
    if (s.contains('rate limit')) return 'Too many tries. Please wait a few minutes.';
    return m;
  }

  // ------------------------------------------------------------- lifecycle
  Future<void> _start() async {
    final uid = user?.id;
    if (uid == null || _started) return;
    _started = true;

    // A different account signed in on this device: start from its data.
    final lastUser = _prefs?.getString('mutiny.sync.lastUser');
    final firstSync = !(_prefs?.containsKey('mutiny.sync.state.$uid') ?? false);
    if (lastUser != null && lastUser != uid) await library.clearAll();
    await _prefs?.setString('mutiny.sync.lastUser', uid);
    _loadState(uid);

    library.addListener(_onLocalChange);
    _subscribe(uid);
    await fullSync(firstSync: firstSync && (lastUser == null || lastUser == uid));
  }

  void _stop() {
    _started = false;
    library.removeListener(_onLocalChange);
    _debounce?.cancel();
    _retry?.cancel();
    if (_channel != null) unawaited(_client?.removeChannel(_channel!));
    _channel = null;
    status = SyncStatus.signedOut;
  }

  /// Call when the app comes back to the foreground.
  void onResume() {
    if (signedIn && _started) unawaited(fullSync());
  }

  void _loadState(String uid) {
    try {
      final raw = _prefs?.getString('mutiny.sync.state.$uid');
      final j = raw == null ? const {} : jsonDecode(raw) as Map;
      _synced = Map<String, String>.from((j['synced'] as Map?) ?? const {});
      _files = Map<String, String>.from((j['files'] as Map?) ?? const {});
    } catch (_) {
      _synced = {};
      _files = {};
    }
  }

  Future<void> _saveState() async {
    final uid = user?.id;
    if (uid == null) return;
    await _prefs?.setString('mutiny.sync.state.$uid', jsonEncode({'synced': _synced, 'files': _files}));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => op()).catchError((Object e) {
      debugPrint('Sync error: $e');
      status = SyncStatus.offline;
      error = "Can't reach the cloud right now. Changes will sync later.";
      notifyListeners();
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 45), () => unawaited(fullSync()));
    });
    _queue = next;
    return next;
  }

  // ----------------------------------------------------------------- sync
  /// Pulls everything, merges with this device and pushes the result.
  Future<void> fullSync({bool firstSync = false}) => _enqueue(() async {
        final c = _client;
        final uid = user?.id;
        if (c == null || uid == null) return;
        status = SyncStatus.syncing;
        error = null;
        notifyListeners();

        final rows = await c.from(CloudConfig.table).select('kind,item_id,data,deleted');
        final remote = <String, Map<String, dynamic>?>{};
        for (final row in rows) {
          final key = '${row['kind']}/${row['item_id']}';
          remote[key] = row['deleted'] == true || row['data'] == null ? null : Map<String, dynamic>.from(row['data'] as Map);
        }

        final local = _localCloudForm(uid);
        final plan = SyncMerge.plan(local: local, remote: remote, synced: _synced, firstSync: firstSync);

        _applying = true;
        try {
          for (final e in plan.apply.entries) {
            library.applySynced(e.key, e.value == null ? null : _fromCloud(e.value!), notify: false);
          }
        } finally {
          _applying = false;
        }
        if (plan.apply.isNotEmpty) library.refresh();

        await _push(plan.push, uid);

        // Everything now matches the cloud.
        _synced = {
          for (final e in _localCloudForm(uid).entries) e.key: SyncMerge.hash(e.value),
        };
        await _saveState();
        status = SyncStatus.synced;
        lastSync = DateTime.now();
        notifyListeners();
      });

  void _onLocalChange() {
    if (_applying || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () => unawaited(_pushChanges()));
  }

  Future<void> _flush() async {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      await _pushChanges();
    }
    await _queue;
  }

  /// Sends only what changed on this device since the last sync.
  Future<void> _pushChanges() => _enqueue(() async {
        final uid = user?.id;
        if (uid == null) return;
        final local = _localCloudForm(uid);
        final changes = <String, Map<String, dynamic>?>{};
        for (final e in local.entries) {
          if (_synced[e.key] != SyncMerge.hash(e.value)) changes[e.key] = e.value;
        }
        for (final key in _synced.keys) {
          if (!local.containsKey(key)) changes[key] = null;
        }
        if (changes.isEmpty) return;
        status = SyncStatus.syncing;
        notifyListeners();
        await _push(changes, uid);
        for (final e in changes.entries) {
          if (e.value == null) {
            _synced.remove(e.key);
          } else {
            _synced[e.key] = SyncMerge.hash(e.value);
          }
        }
        await _saveState();
        status = SyncStatus.synced;
        lastSync = DateTime.now();
        error = null;
        notifyListeners();
      });

  Future<void> _push(Map<String, Map<String, dynamic>?> changes, String uid) async {
    if (changes.isEmpty) return;
    for (final data in changes.values) {
      if (data != null) await _uploadFilesIn(data, uid);
    }
    final rows = [
      for (final e in changes.entries)
        {
          'user_id': uid,
          'kind': SyncMerge.kindOf(e.key),
          'item_id': e.key.substring(e.key.indexOf('/') + 1),
          'data': e.value,
          'deleted': e.value == null,
        },
    ];
    for (var i = 0; i < rows.length; i += 100) {
      await _client!.from(CloudConfig.table).upsert(rows.sublist(i, (i + 100).clamp(0, rows.length)), onConflict: 'user_id,kind,item_id');
    }
  }

  void _subscribe(String uid) {
    _channel = _client!
        .channel('library-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: CloudConfig.table,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (payload) => _onRemoteRow(payload.newRecord),
        )
        .subscribe();
  }

  void _onRemoteRow(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final key = '${row['kind']}/${row['item_id']}';
    final deleted = row['deleted'] == true || row['data'] == null;
    final data = deleted ? null : Map<String, dynamic>.from(row['data'] as Map);
    final h = data == null ? null : SyncMerge.hash(data);
    if (h == _synced[key] || (deleted && !_synced.containsKey(key))) return; // our own echo
    _applying = true;
    try {
      library.applySynced(key, data == null ? null : _fromCloud(data));
    } finally {
      _applying = false;
    }
    if (h == null) {
      _synced.remove(key);
    } else {
      _synced[key] = h;
    }
    unawaited(_saveState());
    lastSync = DateTime.now();
    notifyListeners();
  }

  // ---------------------------------------------------------------- files
  bool _isOurFile(String s) => _docs != null && s.startsWith(_docs!) && !s.startsWith('http');

  String _cloudPathFor(String local, String uid) =>
      _files[local] ?? '$uid/${local.split(Platform.pathSeparator).last}';

  /// This device's items with local file paths swapped for `cloud:` paths.
  Map<String, Map<String, dynamic>> _localCloudForm(String uid) {
    Object? conv(Object? v) {
      if (v is String && _isOurFile(v)) return 'cloud:${_cloudPathFor(v, uid)}';
      if (v is Map) return {for (final e in v.entries) '${e.key}': conv(e.value)};
      if (v is List) return v.map(conv).toList();
      return v;
    }

    return library.syncSnapshot().map((k, v) => MapEntry(k, Map<String, dynamic>.from(conv(v) as Map)));
  }

  /// Cloud item with `cloud:` paths swapped for files on this device
  /// (downloading any that are missing in the background).
  Map<String, dynamic> _fromCloud(Map<String, dynamic> data) {
    Object? conv(Object? v) {
      if (v is String && v.startsWith('cloud:') && _docs != null) {
        final cloud = v.substring(6);
        for (final e in _files.entries) {
          if (e.value == cloud && File(e.key).existsSync()) return e.key;
        }
        final local = '$_docs${Platform.pathSeparator}mutiny_cloud${Platform.pathSeparator}${cloud.split('/').last}';
        _files[local] = cloud;
        if (!File(local).existsSync()) unawaited(_download(cloud, local));
        return local;
      }
      if (v is Map) return {for (final e in v.entries) '${e.key}': conv(e.value)};
      if (v is List) return v.map(conv).toList();
      return v;
    }

    return Map<String, dynamic>.from(conv(data) as Map);
  }

  Future<void> _uploadFilesIn(Map<String, dynamic> data, String uid) async {
    final paths = <String>{};
    void walk(Object? v) {
      if (v is String && v.startsWith('cloud:')) paths.add(v.substring(6));
      if (v is Map) v.values.forEach(walk);
      if (v is List) v.forEach(walk);
    }

    walk(data);
    for (final cloud in paths) {
      if (_files.values.contains(cloud) && (_prefs?.getBool('mutiny.sync.up.$cloud') ?? false)) continue;
      final local = _localPathFor(cloud, uid);
      if (local == null) continue;
      final f = File(local);
      if (!f.existsSync() || f.lengthSync() > CloudConfig.maxFileBytes) continue;
      await _client!.storage.from(CloudConfig.bucket).upload(cloud, f, fileOptions: const FileOptions(upsert: true));
      _files[local] = cloud;
      await _prefs?.setBool('mutiny.sync.up.$cloud', true);
    }
  }

  String? _localPathFor(String cloud, String uid) {
    for (final e in _files.entries) {
      if (e.value == cloud) return e.key;
    }
    // Not mapped yet: find the file by name in our folders.
    final name = cloud.split('/').last;
    for (final dir in ['mutiny_images', 'mutiny_music', 'mutiny_cloud']) {
      final p = '$_docs${Platform.pathSeparator}$dir${Platform.pathSeparator}$name';
      if (File(p).existsSync()) {
        _files[p] = cloud;
        return p;
      }
    }
    return null;
  }

  Future<void> _download(String cloud, String local) async {
    pendingDownloads++;
    notifyListeners();
    try {
      final bytes = await _client!.storage.from(CloudConfig.bucket).download(cloud);
      final f = File(local);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      await _prefs?.setBool('mutiny.sync.up.$cloud', true);
      library.refresh(); // covers/songs can show now
    } catch (e) {
      debugPrint('Download failed for $cloud: $e');
    } finally {
      pendingDownloads--;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stop();
    super.dispose();
  }
}
