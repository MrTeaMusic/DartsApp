import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

/// Ergebnis eines Abgleichs oder Imports.
class MergeResult {
  const MergeResult({
    this.players = 0,
    this.sessions = 0,
    this.throws = 0,
    this.goals = 0,
    this.skipped = 0,
    this.updated = 0,
  });

  /// Neu angelegte Profile, Sessions, Würfe und Ziele.
  final int players;
  final int sessions;
  final int throws;
  final int goals;

  /// Sessions, die schon vorhanden waren.
  final int skipped;

  /// Geänderte oder gelöschte Profile und Ziele.
  final int updated;

  bool get changedAnything => players + sessions + goals + updated > 0;

  MergeResult operator +(MergeResult o) => MergeResult(
        players: players + o.players,
        sessions: sessions + o.sessions,
        throws: throws + o.throws,
        goals: goals + o.goals,
        skipped: skipped + o.skipped,
        updated: updated + o.updated,
      );

  Map<String, int> toJson() =>
      {'players': players, 'sessions': sessions, 'throws': throws, 'goals': goals, 'skipped': skipped, 'updated': updated};

  static MergeResult fromJson(Map<String, Object?> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return MergeResult(
      players: n('players'),
      sessions: n('sessions'),
      throws: n('throws'),
      goals: n('goals'),
      skipped: n('skipped'),
      updated: n('updated'),
    );
  }
}

/// Was ein Gerät hat: alle Profile und Ziele (klein, inklusive gelöschter)
/// und die IDs der abgeschlossenen Sessions.
class SyncManifest {
  const SyncManifest({required this.players, required this.goals, required this.sessionUids});
  final List<Map<String, Object?>> players;
  final List<Map<String, Object?>> goals;
  final Set<String> sessionUids;

  Map<String, Object?> toJson() => {'players': players, 'goals': goals, 'sessions': sessionUids.toList()};

  static SyncManifest fromJson(Map<String, Object?> j) => SyncManifest(
        players: _maps(j['players']),
        goals: _maps(j['goals']),
        sessionUids: {for (final u in (j['sessions'] as List? ?? const [])) if (u is String) u},
      );
}

List<Map<String, Object?>> _maps(Object? l) =>
    l is List ? [for (final e in l) if (e is Map) Map<String, Object?>.from(e)] : const [];

/// Datenpaket für Abgleich und Backup. Flache Listen mit
/// geräteübergreifenden IDs (`uid`, `playerUid`, `sessionUid`).
///
/// Ältere Backups (Version 1) haben keine `uid`; dann wird wie früher über
/// Profilnamen und Startzeit zugeordnet, verknüpft über die lokalen `id`s.
class SyncBundle {
  const SyncBundle({this.players = const [], this.sessions = const [], this.throws = const [], this.goals = const []});
  final List<Map<String, Object?>> players;
  final List<Map<String, Object?>> sessions;
  final List<Map<String, Object?>> throws;
  final List<Map<String, Object?>> goals;

  Map<String, Object?> toJson() => {'players': players, 'sessions': sessions, 'throws': throws, 'goals': goals};

  static SyncBundle fromJson(Map<String, Object?> j) => SyncBundle(
        players: _maps(j['players']),
        sessions: _maps(j['sessions']),
        throws: _maps(j['throws']),
        goals: _maps(j['goals']),
      );
}

/// Liest und schreibt die Daten geräteübergreifend.
///
/// Regeln beim Zusammenführen:
/// * Sessions ändern sich nach dem Abschluss nicht mehr: fehlende werden
///   übernommen, vorhandene übersprungen.
/// * Profile und Ziele: die neueste Änderung gewinnt (`updatedAt`). Gelöscht
///   wird über eine Markierung (`deletedAt`), damit es weitergegeben wird.
/// * Gleich benannte Profile bzw. gleiche Zielart auf zwei Geräten werden zu
///   einem; beide Seiten übernehmen die kleinere `uid` und landen so beim
///   selben Ergebnis.
class SyncStore {
  SyncStore(this.db);
  final AppDatabase db;

  // ------------------------------------------------------------ Lesen

  Future<SyncManifest> manifest() async {
    final players = await db.select(db.players).get();
    final byId = {for (final p in players) p.id: p.uid};
    final goals = await db.select(db.goals).get();
    final sessions = await (db.selectOnly(db.sessions)
          ..addColumns([db.sessions.uid])
          ..where(db.sessions.endedAt.isNotNull()))
        .map((r) => r.read(db.sessions.uid)!)
        .get();
    return SyncManifest(
      players: [for (final p in players) _player(p)],
      goals: [for (final g in goals) if (byId[g.playerId] != null) _goal(g, byId[g.playerId]!)],
      sessionUids: sessions.toSet(),
    );
  }

  static const _signatureSql = '''
SELECT
  (SELECT count(*) FROM sessions WHERE ended_at IS NOT NULL) || ':' ||
  (SELECT count(*) || '-' || coalesce(max(coalesce(updated_at, created_at)), 0) FROM players) || ':' ||
  (SELECT count(*) || '-' || coalesce(max(coalesce(updated_at, created_at)), 0) FROM goals) AS sig''';

  /// Kurzer Fingerabdruck dessen, was abgeglichen wird. Ändert er sich, gibt
  /// es etwas Neues (abgeschlossene Session, Profil oder Ziel geändert).
  Future<String> signature() => db.customSelect(_signatureSql).map((r) => r.read<String>('sig')).getSingle();

  Stream<String> watchSignature() => db
      .customSelect(_signatureSql, readsFrom: {db.sessions, db.players, db.goals})
      .map((r) => r.read<String>('sig'))
      .watchSingle();

  /// Paket mit Profilen, Zielen und den Sessions (samt Würfen). Ohne
  /// [sessionUids] alle, mit [playerId] nur ein Profil. [includeOpen] nimmt
  /// auch laufende Sessions mit (fürs Backup).
  Future<SyncBundle> bundle({Iterable<String>? sessionUids, int? playerId, bool includeOpen = false}) async {
    final players = await (db.select(db.players)..where((p) => playerId == null ? const Constant(true) : p.id.equals(playerId))).get();
    final playerUids = {for (final p in await db.select(db.players).get()) p.id: p.uid};
    final wanted = sessionUids?.toSet();
    final sessions = <SessionRow>[];
    if (wanted == null || wanted.isNotEmpty) {
      final q = db.select(db.sessions)
        ..where((s) {
          Expression<bool> e = const Constant(true);
          if (!includeOpen) e = e & s.endedAt.isNotNull();
          if (playerId != null) e = e & s.playerId.equals(playerId);
          if (wanted != null) e = e & s.uid.isIn(wanted);
          return e;
        })
        ..orderBy([(s) => OrderingTerm.asc(s.id)]);
      sessions.addAll(await q.get());
    }
    final sessionUid = {for (final s in sessions) s.id: s.uid};
    final throws = sessionUid.isEmpty
        ? const <ThrowRow>[]
        : await (db.select(db.throws)
              ..where((t) => t.sessionId.isIn(sessionUid.keys))
              ..orderBy([(t) => OrderingTerm.asc(t.sessionId), (t) => OrderingTerm.asc(t.seq)]))
            .get();
    final goals = await (db.select(db.goals)..where((g) => playerId == null ? const Constant(true) : g.playerId.equals(playerId))).get();
    return SyncBundle(
      players: [for (final p in players) _player(p)],
      sessions: [for (final s in sessions) _session(s, playerUids[s.playerId]!)],
      throws: [for (final t in throws) _throw(t, sessionUid[t.sessionId]!, playerUids[t.playerId]!)],
      goals: [for (final g in goals) if (playerUids[g.playerId] != null) _goal(g, playerUids[g.playerId]!)],
    );
  }

  static String? _time(DateTime? t) => t?.toUtc().toIso8601String();
  /// ISO-Text (Version 2) oder Millisekunden (drift-JSON in Version 1).
  static DateTime? _parse(Object? v) => switch (v) {
        String() => DateTime.tryParse(v)?.toLocal(),
        num() => DateTime.fromMillisecondsSinceEpoch(v.toInt()),
        _ => null,
      };

  Map<String, Object?> _player(Player p) => {
        'id': p.id,
        'uid': p.uid,
        'name': p.name,
        'createdAt': _time(p.createdAt),
        'updatedAt': _time(p.updatedAt),
        'deletedAt': _time(p.deletedAt),
      };

  Map<String, Object?> _goal(GoalRow g, String playerUid) => {
        'id': g.id,
        'uid': g.uid,
        'playerId': g.playerId,
        'playerUid': playerUid,
        'kind': g.kind,
        'target': g.target,
        'createdAt': _time(g.createdAt),
        'updatedAt': _time(g.updatedAt),
        'deletedAt': _time(g.deletedAt),
      };

  Map<String, Object?> _session(SessionRow s, String playerUid) => {
        'id': s.id,
        'uid': s.uid,
        'playerId': s.playerId,
        'playerUid': playerUid,
        'gameId': s.gameId,
        'configJson': s.configJson,
        'seed': s.seed,
        'startedAt': _time(s.startedAt),
        'endedAt': _time(s.endedAt),
        'finished': s.finished,
        'resultJson': s.resultJson,
        'dartCount': s.dartCount,
      };

  Map<String, Object?> _throw(ThrowRow t, String sessionUid, String playerUid) => {
        'sessionId': t.sessionId,
        'sessionUid': sessionUid,
        'playerId': t.playerId,
        'playerUid': playerUid,
        'gameId': t.gameId,
        'seq': t.seq,
        'visitIndex': t.visitIndex,
        'counted': t.counted,
        'segment': t.segment,
        'number': t.number,
        'multiplier': t.multiplier,
        'bed': t.bed,
        'score': t.score,
        'x': t.x,
        'y': t.y,
        'source': t.source,
        'timestamp': _time(t.timestamp),
        'rawJson': t.rawJson,
      };

  // ------------------------------------------------------- Zusammenführen

  /// Führt ein Paket mit den vorhandenen Daten zusammen.
  Future<MergeResult> merge(SyncBundle bundle) => db.transaction(() async {
        final players = await _mergePlayers(bundle.players);
        final goals = await _mergeGoals(bundle.goals, players);
        final sessions = await _mergeSessions(bundle.sessions, bundle.throws, players);
        return players.result + goals + sessions;
      });

  /// Nur Profile und Ziele (aus einem Manifest).
  Future<MergeResult> mergeMeta(SyncManifest m) => db.transaction(() async {
        final players = await _mergePlayers(m.players);
        final goals = await _mergeGoals(m.goals, players);
        return players.result + goals;
      });

  static DateTime _stamp(DateTime created, DateTime? updated) => updated ?? created;

  /// Ist die fremde Änderung neuer? Zeiten speichert die Datenbank nur auf die
  /// Sekunde; bei Gleichstand entscheidet [tie] (> 0: fremd gewinnt), damit
  /// alle Geräte zum selben Ergebnis kommen.
  static bool _newer(DateTime theirs, DateTime ours, int tie) =>
      theirs.isAfter(ours) || (theirs.isAtSameMomentAs(ours) && tie > 0);

  Future<_PlayerMap> _mergePlayers(List<Map<String, Object?>> incoming) async {
    final map = _PlayerMap();
    var created = 0;
    var updated = 0;
    for (final j in incoming) {
      final uid = j['uid'] as String?;
      final name = (j['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final createdAt = _parse(j['createdAt']) ?? DateTime.now();
      final updatedAt = _parse(j['updatedAt']);
      final deletedAt = _parse(j['deletedAt']);
      final all = await db.select(db.players).get();

      var local = uid == null ? null : all.where((p) => p.uid == uid).firstOrNull;
      if (local == null && deletedAt == null) {
        local = all.where((p) => p.deletedAt == null && p.name == name).firstOrNull;
        // Gleiches Profil auf zwei Geräten angelegt: beide nehmen die kleinere uid.
        if (local != null && uid != null && uid.compareTo(local.uid) < 0) {
          await (db.update(db.players)..where((p) => p.id.equals(local!.id))).write(PlayersCompanion(uid: Value(uid)));
        }
      }

      if (local == null) {
        final id = await db.into(db.players).insert(PlayersCompanion.insert(
              name: name.length > 40 ? name.substring(0, 40) : name,
              createdAt: createdAt,
              uid: uid == null ? const Value.absent() : Value(uid),
              updatedAt: Value(updatedAt),
              deletedAt: Value(deletedAt),
            ));
        map.add(j, id, deleted: deletedAt != null);
        if (deletedAt == null) created++;
        continue;
      }

      var deleted = local.deletedAt != null;
      if (!deleted && deletedAt != null && !deletedAt.isBefore(_stamp(local.createdAt, local.updatedAt))) {
        deleted = await _deletePlayer(local.id, deletedAt);
        if (deleted) updated++;
      } else if (!deleted &&
          deletedAt == null &&
          updatedAt != null &&
          _newer(updatedAt, _stamp(local.createdAt, local.updatedAt), name.compareTo(local.name))) {
        await (db.update(db.players)..where((p) => p.id.equals(local!.id)))
            .write(PlayersCompanion(name: Value(name), updatedAt: Value(updatedAt)));
        updated++;
      }
      map.add(j, local.id, deleted: deleted);
    }
    map.result = MergeResult(players: created, updated: updated);
    return map;
  }

  /// Löscht ein Profil wie auf dem Gerät selbst; das letzte aktive Profil
  /// bleibt erhalten.
  Future<bool> _deletePlayer(int id, DateTime at) async {
    final active = await (db.select(db.players)..where((p) => p.deletedAt.isNull())).get();
    if (active.length <= 1) return false;
    await (db.delete(db.sessions)..where((s) => s.playerId.equals(id))).go();
    await (db.delete(db.throws)..where((t) => t.playerId.equals(id))).go();
    await (db.delete(db.goals)..where((g) => g.playerId.equals(id))).go();
    await (db.update(db.players)..where((p) => p.id.equals(id)))
        .write(PlayersCompanion(isDefault: const Value(false), deletedAt: Value(at), updatedAt: Value(at)));
    final rest = active.where((p) => p.id != id).toList();
    if (!rest.any((p) => p.isDefault)) {
      await (db.update(db.players)..where((p) => p.id.equals(rest.first.id))).write(const PlayersCompanion(isDefault: Value(true)));
    }
    return true;
  }

  Future<MergeResult> _mergeGoals(List<Map<String, Object?>> incoming, _PlayerMap players) async {
    var created = 0;
    var updated = 0;
    for (final j in incoming) {
      final player = await players.resolve(this, j);
      if (player == null || player.deleted) continue;
      final uid = j['uid'] as String?;
      final kind = j['kind'] as String?;
      final target = (j['target'] as num?)?.toDouble();
      if (kind == null || target == null) continue;
      final createdAt = _parse(j['createdAt']) ?? DateTime.now();
      final updatedAt = _parse(j['updatedAt']);
      final deletedAt = _parse(j['deletedAt']);

      var local = uid == null ? null : await (db.select(db.goals)..where((g) => g.uid.equals(uid))).getSingleOrNull();
      if (local == null) {
        // Gleiche Zielart schon vorhanden: als dasselbe Ziel behandeln.
        local = await (db.select(db.goals)
              ..where((g) => g.playerId.equals(player.id) & g.kind.equals(kind) & g.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
        if (local != null && uid != null && uid.compareTo(local.uid) < 0) {
          await (db.update(db.goals)..where((g) => g.id.equals(local!.id))).write(GoalsCompanion(uid: Value(uid)));
        }
      }
      if (local == null) {
        await db.into(db.goals).insert(GoalsCompanion.insert(
              playerId: player.id,
              kind: kind,
              target: target,
              createdAt: createdAt,
              uid: uid == null ? const Value.absent() : Value(uid),
              updatedAt: Value(updatedAt),
              deletedAt: Value(deletedAt),
            ));
        if (deletedAt == null) created++;
        continue;
      }
      final theirs = _stamp(createdAt, updatedAt);
      final differs = target != local.target || (deletedAt == null) != (local.deletedAt == null);
      // Gleichstand: Löschen gewinnt, sonst das größere Ziel.
      final tie = deletedAt != null && local.deletedAt == null ? 1 : target.compareTo(local.target);
      if (differs && _newer(theirs, _stamp(local.createdAt, local.updatedAt), tie)) {
        await (db.update(db.goals)..where((g) => g.id.equals(local!.id)))
            .write(GoalsCompanion(target: Value(target), updatedAt: Value(theirs), deletedAt: Value(deletedAt)));
        updated++;
      }
    }
    return MergeResult(goals: created, updated: updated);
  }

  Future<MergeResult> _mergeSessions(
    List<Map<String, Object?>> incoming,
    List<Map<String, Object?>> throws,
    _PlayerMap players,
  ) async {
    final throwsBySession = <Object, List<Map<String, Object?>>>{};
    for (final t in throws) {
      final key = t['sessionUid'] ?? t['sessionId'];
      if (key != null) (throwsBySession[key] ??= []).add(t);
    }
    var created = 0;
    var newThrows = 0;
    var skipped = 0;
    for (final j in incoming) {
      final player = await players.resolve(this, j);
      if (player == null || player.deleted) continue;
      final uid = j['uid'] as String?;
      final gameId = j['gameId'] as String;
      final seed = (j['seed'] as num).toInt();
      final startedAt = _parse(j['startedAt']) ?? DateTime.now();

      final byUid = uid == null ? null : await (db.select(db.sessions)..where((s) => s.uid.equals(uid))).getSingleOrNull();
      final dup = byUid ??
          await (db.select(db.sessions)
                ..where((x) =>
                    x.playerId.equals(player.id) &
                    x.gameId.equals(gameId) &
                    x.startedAt.equals(startedAt) &
                    x.seed.equals(seed))
                ..limit(1))
              .getSingleOrNull();
      if (dup != null) {
        skipped++;
        continue;
      }
      final sessionId = await db.into(db.sessions).insert(SessionsCompanion.insert(
            playerId: player.id,
            gameId: gameId,
            configJson: j['configJson'] as String? ?? '{}',
            seed: seed,
            startedAt: startedAt,
            endedAt: Value(_parse(j['endedAt'])),
            finished: Value(j['finished'] == true),
            resultJson: Value(j['resultJson'] as String?),
            dartCount: Value((j['dartCount'] as num?)?.toInt() ?? 0),
            uid: uid == null ? const Value.absent() : Value(uid),
          ));
      created++;
      final own = throwsBySession[uid ?? j['id']] ?? const [];
      await db.batch((b) {
        for (final t in own) {
          b.insert(
            db.throws,
            ThrowsCompanion.insert(
              sessionId: sessionId,
              playerId: player.id,
              gameId: t['gameId'] as String? ?? gameId,
              seq: (t['seq'] as num).toInt(),
              visitIndex: (t['visitIndex'] as num).toInt(),
              counted: Value(t['counted'] != false),
              segment: t['segment'] as String,
              number: (t['number'] as num).toInt(),
              multiplier: (t['multiplier'] as num).toInt(),
              bed: t['bed'] as String,
              score: (t['score'] as num).toInt(),
              x: Value((t['x'] as num?)?.toDouble()),
              y: Value((t['y'] as num?)?.toDouble()),
              source: t['source'] as String,
              timestamp: _parse(t['timestamp']) ?? startedAt,
              rawJson: Value(t['rawJson'] as String?),
            ),
          );
        }
      });
      newThrows += own.length;
    }
    return MergeResult(sessions: created, throws: newThrows, skipped: skipped);
  }
}

class _LocalPlayer {
  const _LocalPlayer(this.id, {required this.deleted});
  final int id;
  final bool deleted;
}

/// Zuordnung fremder Profile (über `uid` oder alte `id`) zu lokalen.
class _PlayerMap {
  final Map<String, _LocalPlayer> _byUid = {};
  final Map<int, _LocalPlayer> _byId = {};
  MergeResult result = const MergeResult();

  void add(Map<String, Object?> j, int localId, {required bool deleted}) {
    final p = _LocalPlayer(localId, deleted: deleted);
    final uid = j['uid'];
    if (uid is String) _byUid[uid] = p;
    final id = j['id'];
    if (id is num) _byId[id.toInt()] = p;
  }

  /// Lokales Profil zu einer Session oder einem Ziel. Profile, die nicht im
  /// Paket stehen, werden lokal über die `uid` gesucht.
  Future<_LocalPlayer?> resolve(SyncStore store, Map<String, Object?> j) async {
    final uid = j['playerUid'];
    if (uid is String) {
      final known = _byUid[uid];
      if (known != null) return known;
      final row = await (store.db.select(store.db.players)..where((p) => p.uid.equals(uid))).getSingleOrNull();
      if (row == null) return null;
      return _byUid[uid] = _LocalPlayer(row.id, deleted: row.deletedAt != null);
    }
    final id = j['playerId'];
    return id is num ? _byId[id.toInt()] : null;
  }
}

final syncStoreProvider = Provider<SyncStore>((ref) => SyncStore(ref.watch(appDatabaseProvider)));
