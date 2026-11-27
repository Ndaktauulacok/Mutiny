import 'dart:convert';

/// Pure sync logic (no network), so it can be tested.
///
/// Every synced item has a key like `playlist/123` or `liked/all` and a JSON
/// value. We remember the hash of each item as it was at the last successful
/// sync; comparing local and remote hashes against it tells us who changed.
class SyncMerge {
  /// Items that are whole lists; when both sides changed they are combined
  /// instead of one side winning, so nothing liked on one device is lost.
  static const listKinds = {'liked', 'artist', 'saved_playlist', 'station', 'recent'};

  static String kindOf(String key) => key.substring(0, key.indexOf('/'));

  /// Stable hash of a JSON value, independent of key order (Postgres jsonb
  /// re-orders keys).
  static String hash(Object? json) {
    final s = jsonEncode(canonical(json));
    // FNV-1a 64-bit
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(s)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16);
  }

  static Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return v.map(canonical).toList();
    if (v is double && v == v.roundToDouble()) return v.toInt();
    return v;
  }

  /// Combines two list items, remote order first, adding local-only items.
  static Map<String, dynamic> unionLists(Map<String, dynamic> remote, Map<String, dynamic> local) {
    String id(Object? e) {
      if (e is Map) return '${e['source'] ?? ''}:${e['id']}';
      return '$e';
    }

    final r = (remote['items'] as List?) ?? const [];
    final l = (local['items'] as List?) ?? const [];
    final seen = r.map(id).toSet();
    return {
      'items': [...r, ...l.where((e) => !seen.contains(id(e)))],
    };
  }

  /// Decides what to do for every key.
  ///
  /// [local]: this device's items (cloud form). [remote]: key → data, or
  /// null for a deleted item (keys missing = never existed in the cloud).
  /// [synced]: key → hash at the last successful sync.
  /// [firstSync]: this device has never synced with this account.
  static MergePlan plan({
    required Map<String, Map<String, dynamic>> local,
    required Map<String, Map<String, dynamic>?> remote,
    required Map<String, String> synced,
    bool firstSync = false,
  }) {
    final apply = <String, Map<String, dynamic>?>{};
    final push = <String, Map<String, dynamic>?>{};
    final keys = {...local.keys, ...remote.keys};

    for (final key in keys) {
      final l = local[key];
      final hasRemote = remote.containsKey(key);
      final r = remote[key];
      final s = synced[key];
      final hl = l == null ? null : hash(l);
      final hr = r == null ? null : hash(r);

      if (l != null && r != null) {
        if (hl == hr) continue;
        if (hl == s) {
          apply[key] = r; // only the cloud changed
        } else if (hr == s && !firstSync) {
          push[key] = l; // only this device changed
        } else if (listKinds.contains(kindOf(key))) {
          final merged = unionLists(r, l);
          apply[key] = merged;
          push[key] = merged;
        } else {
          apply[key] = r; // both changed: the account's copy wins
        }
      } else if (l == null && r != null) {
        if (s != null && !firstSync) {
          push[key] = null; // deleted here since the last sync
        } else {
          apply[key] = r;
        }
      } else if (l != null && hasRemote && r == null) {
        if (hl == s) {
          apply[key] = null; // deleted on another device
        } else {
          push[key] = l; // changed here after it was deleted elsewhere: keep it
        }
      } else if (l != null && !hasRemote) {
        push[key] = l;
      }
    }
    return MergePlan(apply: apply, push: push);
  }
}

class MergePlan {
  /// Changes to make on this device (null = delete).
  final Map<String, Map<String, dynamic>?> apply;

  /// Changes to send to the cloud (null = delete).
  final Map<String, Map<String, dynamic>?> push;

  const MergePlan({required this.apply, required this.push});
}
