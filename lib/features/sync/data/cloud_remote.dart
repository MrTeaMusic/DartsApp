import 'dart:convert';

import 'cloud_api.dart';
import 'cloud_crypto.dart';
import 'sync_client.dart';
import 'sync_store.dart';

/// Gleicht über den verschlüsselten Cloud-Speicher ab statt über einen Hub.
///
/// Im Speicher liegt je Session ein Block (Session, ihre Würfe und ihr Profil)
/// und eine Meta mit dem [SyncManifest] (Profile, Ziele, Pläne, Erfolge,
/// Challenges, Session-IDs mit Ständen, Löschmarkierungen). Beides ist mit
/// dem Datenschlüssel verschlüsselt. Den Hub-Teil, das Zusammenführen,
/// übernimmt dieses Gerät: Es liest die Meta, holt und schickt Sessions und
/// schreibt am Ende die zusammengeführte Meta zurück, und zwar nur, wenn sie
/// noch in der Fassung ist, die es gelesen hat. Hat ein anderes Gerät
/// inzwischen geschrieben, läuft der Abgleich noch einmal ([commit] gibt
/// `false` zurück).
class CloudRemote extends SyncRemote {
  CloudRemote(this.api, this.keys, {this.parallel = 4});

  final CloudApi api;
  final CloudKeys keys;

  /// Gleichzeitige Anfragen beim Hoch- und Herunterladen.
  final int parallel;

  int _rev = 0;

  @override
  void close() => api.close();

  Future<Map<String, Object?>> _open(String body, String label) async {
    try {
      return await keys.open(body, label);
    } on CloudDecryptException {
      throw const SyncException(SyncFailure.wrongSecret);
    }
  }

  /// Gibt es den Tresor schon? Für das Verbinden eines weiteren Geräts.
  Future<bool> vaultExists() async => await api.getMeta() != null;

  @override
  Future<({SyncManifest manifest, MergeResult result})> exchange(SyncManifest mine) async {
    final meta = await api.getMeta();
    _rev = meta?.rev ?? 0;
    final theirs = meta == null
        ? const SyncManifest(players: [], goals: [], sessionUids: {}, sessionRevisions: {})
        : SyncManifest.fromJson(await _open(meta.body, 'meta'));
    return (manifest: theirs, result: const MergeResult());
  }

  @override
  Future<MergeResult> push(SyncBundle bundle) async {
    final playerByUid = {for (final p in bundle.players) p['uid']: p};
    final throwsByUid = <Object?, List<Map<String, Object?>>>{};
    for (final t in bundle.throws) {
      (throwsByUid[t['sessionUid']] ??= []).add(t);
    }
    var stored = 0;
    await _pool(bundle.sessions, (s) async {
      final uid = s['uid'] as String;
      final throws = throwsByUid[uid] ?? const [];
      final owner = playerByUid[s['playerUid']];
      final body = await keys.seal({
        'players': [?owner],
        'sessions': [s],
        'throws': throws,
      }, 's:$uid');
      final stamp = DateTime.tryParse('${s['updatedAt']}')?.millisecondsSinceEpoch ?? 0;
      final darts = (s['dartCount'] as num?)?.toInt() ?? throws.length;
      if (await api.putSession(uid, CloudObject(stamp: stamp, darts: darts, body: body))) stored++;
    });
    return MergeResult(sessions: stored);
  }

  @override
  Future<SyncBundle> pull(List<String> uids) async {
    final players = <String, Map<String, Object?>>{};
    final sessions = <Map<String, Object?>>[];
    final throws = <Map<String, Object?>>[];
    await _pool(uids, (uid) async {
      final object = await api.getSession(uid);
      if (object == null) return;
      final part = SyncBundle.fromJson(await _open(object.body, 's:$uid'));
      for (final p in part.players) {
        players['${p['uid']}'] = p;
      }
      sessions.addAll(part.sessions);
      throws.addAll(part.throws);
    });
    return SyncBundle(players: players.values.toList(), sessions: sessions, throws: throws);
  }

  @override
  Future<bool> commit(SyncStore store, SyncManifest theirs, SyncManifest mine) async {
    final now = await store.manifest();
    if (_rev > 0 && _canonical(now.toJson()) == _canonical(theirs.toJson())) return true;
    final rev = await api.putMeta(_rev, await keys.seal(now.toJson(), 'meta'));
    if (rev == null) return false;
    // Was dieses Gerät gelöscht hat, soll auch aus dem Speicher verschwinden.
    final knownDeleted = {for (final d in theirs.deletedSessions) d['uid']};
    for (final d in mine.deletedSessions) {
      final uid = d['uid'];
      if (uid is! String || knownDeleted.contains(uid)) continue;
      try {
        await api.deleteSession(uid);
      } on SyncException {
        // Bleibt als verschlüsselter Block liegen; die Markierung in der Meta
        // verhindert, dass er wieder auftaucht.
      }
    }
    return true;
  }

  /// Arbeitet [items] mit höchstens [parallel] gleichzeitigen Aufrufen ab.
  Future<void> _pool<T>(Iterable<T> items, Future<void> Function(T) f) async {
    final queue = items.iterator;
    Future<void> worker() async {
      while (queue.moveNext()) {
        await f(queue.current);
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  }
}

/// Reihenfolge der Listen und Schlüssel ausgeschlossen, damit zwei gleiche
/// Manifeste auch gleich verglichen werden.
String _canonical(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) => switch (v) {
      Map() => {for (final k in (v.keys.map((e) => '$e').toList()..sort())) k: _sorted(v[k])},
      List() => (v.map(_sorted).toList()..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)))),
      _ => v,
    };
