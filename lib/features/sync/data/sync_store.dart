import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../challenges/domain/challenge_catalog.dart';

/// Ergebnis eines Abgleichs oder Imports.
class MergeResult {
  const MergeResult({
    this.players = 0,
    this.sessions = 0,
    this.throws = 0,
    this.goals = 0,
    this.plans = 0,
    this.achievements = 0,
    this.challenges = 0,
    this.skipped = 0,
    this.updated = 0,
  });

  /// Neu angelegte Profile, Sessions, Würfe und Ziele.
  final int players;
  final int sessions;
  final int throws;
  final int goals;

  /// Neu angelegte eigene Trainingspläne.
  final int plans;

  /// Neue Erfolgs-Stufen und neue bzw. verbesserte Challenge-Ergebnisse.
  final int achievements;
  final int challenges;

  /// Sessions, die schon vorhanden waren.
  final int skipped;

  /// Geänderte oder gelöschte Profile, Ziele und Trainingspläne.
  final int updated;

  bool get changedAnything => players + sessions + goals + plans + achievements + challenges + updated > 0;

  MergeResult operator +(MergeResult o) => MergeResult(
        players: players + o.players,
        sessions: sessions + o.sessions,
        throws: throws + o.throws,
        goals: goals + o.goals,
        plans: plans + o.plans,
        achievements: achievements + o.achievements,
        challenges: challenges + o.challenges,
        skipped: skipped + o.skipped,
        updated: updated + o.updated,
      );

  Map<String, int> toJson() => {
        'players': players,
        'sessions': sessions,
        'throws': throws,
        'goals': goals,
        'plans': plans,
        'achievements': achievements,
        'challenges': challenges,
        'skipped': skipped,
        'updated': updated,
      };

  static MergeResult fromJson(Map<String, Object?> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return MergeResult(
      players: n('players'),
      sessions: n('sessions'),
      throws: n('throws'),
      goals: n('goals'),
      plans: n('plans'),
      achievements: n('achievements'),
      challenges: n('challenges'),
      skipped: n('skipped'),
      updated: n('updated'),
    );
  }
}

/// Was ein Gerät hat: alle Profile, Ziele, eigenen Trainingspläne, Erfolge
/// und Challenge-Ergebnisse (klein, inklusive gelöschter) und die IDs der
/// abgeschlossenen Sessions.
class SyncManifest {
  const SyncManifest({
    required this.players,
    required this.goals,
    this.plans = const [],
    this.achievements = const [],
    this.challenges = const [],
    required this.sessionUids,
  });
  final List<Map<String, Object?>> players;
  final List<Map<String, Object?>> goals;
  final List<Map<String, Object?>> plans;
  final List<Map<String, Object?>> achievements;
  final List<Map<String, Object?>> challenges;
  final Set<String> sessionUids;

  Map<String, Object?> toJson() => {
        'players': players,
        'goals': goals,
        'plans': plans,
        'achievements': achievements,
        'challenges': challenges,
        'sessions': sessionUids.toList(),
      };

  static SyncManifest fromJson(Map<String, Object?> j) => SyncManifest(
        players: _maps(j['players']),
        goals: _maps(j['goals']),
        plans: _maps(j['plans']),
        achievements: _maps(j['achievements']),
        challenges: _maps(j['challenges']),
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
/// Trainingspläne gibt es ab Version 3, Erfolge und Challenge-Ergebnisse
/// ab Version 4; ältere Pakete haben keine.
class SyncBundle {
  const SyncBundle({
    this.players = const [],
    this.sessions = const [],
    this.throws = const [],
    this.goals = const [],
    this.plans = const [],
    this.achievements = const [],
    this.challenges = const [],
  });
  final List<Map<String, Object?>> players;
  final List<Map<String, Object?>> sessions;
  final List<Map<String, Object?>> throws;
  final List<Map<String, Object?>> goals;
  final List<Map<String, Object?>> plans;
  final List<Map<String, Object?>> achievements;
  final List<Map<String, Object?>> challenges;

  Map<String, Object?> toJson() => {
        'players': players,
        'sessions': sessions,
        'throws': throws,
        'goals': goals,
        'plans': plans,
        'achievements': achievements,
        'challenges': challenges,
      };

  static SyncBundle fromJson(Map<String, Object?> j) => SyncBundle(
        players: _maps(j['players']),
        sessions: _maps(j['sessions']),
        throws: _maps(j['throws']),
        goals: _maps(j['goals']),
        plans: _maps(j['plans']),
        achievements: _maps(j['achievements']),
        challenges: _maps(j['challenges']),
      );
}

/// Liest und schreibt die Daten geräteübergreifend.
///
/// Regeln beim Zusammenführen:
/// * Sessions ändern sich nach dem Abschluss nicht mehr: fehlende werden
///   übernommen, vorhandene übersprungen.
/// * Profile und Ziele: die neueste Änderung gewinnt (`updatedAt`). Gelöscht
///   wird über eine Markierung (`deletedAt`), damit es weitergegeben wird.
/// * Eigene Trainingspläne: ebenso, zugeordnet nur über die `uid` (zwei
///   gleich benannte Pläne bleiben zwei Pläne).
/// * Gleich benannte Profile bzw. gleiche Zielart auf zwei Geräten werden zu
///   einem; beide Seiten übernehmen die kleinere `uid` und landen so beim
///   selben Ergebnis.
/// * Erfolge (je Profil, Erfolg und Stufe): fehlende werden übernommen, bei
///   beiden gilt das frühere Datum.
/// * Challenge-Ergebnisse (je Profil und Challenge): mehr Sterne, besserer
///   Bestwert und mehr Versuche gewinnen, jeweils für sich.
class SyncStore {
  SyncStore(this.db);
  final AppDatabase db;

  // ------------------------------------------------------------ Lesen

  Future<SyncManifest> manifest() async {
    final players = await db.select(db.players).get();
    final byId = {for (final p in players) p.id: p.uid};
    final goals = await db.select(db.goals).get();
    final plans = await db.select(db.trainingPlans).get();
    final achievements = await db.select(db.achievements).get();
    final challenges = await db.select(db.challengeResults).get();
    final sessions = await (db.selectOnly(db.sessions)
          ..addColumns([db.sessions.uid])
          ..where(db.sessions.endedAt.isNotNull()))
        .map((r) => r.read(db.sessions.uid)!)
        .get();
    return SyncManifest(
      players: [for (final p in players) _player(p)],
      goals: [for (final g in goals) if (byId[g.playerId] != null) _goal(g, byId[g.playerId]!)],
      plans: [for (final p in plans) _plan(p)],
      achievements: [for (final a in achievements) if (byId[a.playerId] != null) _achievement(a, byId[a.playerId]!)],
      challenges: [for (final c in challenges) if (byId[c.playerId] != null) _challenge(c, byId[c.playerId]!)],
      sessionUids: sessions.toSet(),
    );
  }

  static const _signatureSql = '''
SELECT
  (SELECT count(*) FROM sessions WHERE ended_at IS NOT NULL) || ':' ||
  (SELECT count(*) || '-' || coalesce(max(coalesce(updated_at, created_at)), 0) FROM players) || ':' ||
  (SELECT count(*) || '-' || coalesce(max(coalesce(updated_at, created_at)), 0) FROM goals) || ':' ||
  (SELECT count(*) || '-' || coalesce(max(coalesce(updated_at, created_at)), 0) FROM training_plans) || ':' ||
  (SELECT count(*) FROM achievements) || ':' ||
  (SELECT count(*) || '-' || coalesce(max(updated_at), 0) FROM challenge_results) AS sig''';

  /// Kurzer Fingerabdruck dessen, was abgeglichen wird. Ändert er sich, gibt
  /// es etwas Neues (abgeschlossene Session, Profil, Ziel, Plan, Erfolg oder
  /// Challenge-Ergebnis geändert).
  Future<String> signature() => db.customSelect(_signatureSql).map((r) => r.read<String>('sig')).getSingle();

  Stream<String> watchSignature() => db
      .customSelect(_signatureSql,
          readsFrom: {db.sessions, db.players, db.goals, db.trainingPlans, db.achievements, db.challengeResults})
      .map((r) => r.read<String>('sig'))
      .watchSingle();

  /// Paket mit Profilen, Zielen, eigenen Trainingsplänen und den Sessions
  /// (samt Würfen). Pläne gehören keinem Profil und sind immer dabei. Ohne
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
    final plans = await (db.select(db.trainingPlans)..orderBy([(p) => OrderingTerm.asc(p.id)])).get();
    final achievements =
        await (db.select(db.achievements)..where((a) => playerId == null ? const Constant(true) : a.playerId.equals(playerId))).get();
    final challenges = await (db.select(db.challengeResults)
          ..where((c) => playerId == null ? const Constant(true) : c.playerId.equals(playerId)))
        .get();
    return SyncBundle(
      players: [for (final p in players) _player(p)],
      sessions: [for (final s in sessions) _session(s, playerUids[s.playerId]!)],
      throws: [for (final t in throws) _throw(t, sessionUid[t.sessionId]!, playerUids[t.playerId]!)],
      goals: [for (final g in goals) if (playerUids[g.playerId] != null) _goal(g, playerUids[g.playerId]!)],
      plans: [for (final p in plans) _plan(p)],
      achievements: [for (final a in achievements) if (playerUids[a.playerId] != null) _achievement(a, playerUids[a.playerId]!)],
      challenges: [for (final c in challenges) if (playerUids[c.playerId] != null) _challenge(c, playerUids[c.playerId]!)],
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

  Map<String, Object?> _plan(TrainingPlanRow p) => {
        'uid': p.uid,
        'name': p.name,
        'description': p.description,
        'stepsJson': p.stepsJson,
        'createdAt': _time(p.createdAt),
        'updatedAt': _time(p.updatedAt),
        'deletedAt': _time(p.deletedAt),
      };

  Map<String, Object?> _achievement(AchievementRow a, String playerUid) => {
        'playerUid': playerUid,
        'achievementId': a.achievementId,
        'tier': a.tier,
        'unlockedAt': _time(a.unlockedAt),
      };

  Map<String, Object?> _challenge(ChallengeResultRow c, String playerUid) => {
        'playerUid': playerUid,
        'challengeId': c.challengeId,
        'stars': c.stars,
        'best': c.best,
        'attempts': c.attempts,
        'achievedAt': _time(c.achievedAt),
        'updatedAt': _time(c.updatedAt),
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
        final plans = await _mergePlans(bundle.plans);
        final sessions = await _mergeSessions(bundle.sessions, bundle.throws, players);
        final achievements = await _mergeAchievements(bundle.achievements, players);
        final challenges = await _mergeChallenges(bundle.challenges, players);
        return players.result + goals + plans + sessions + achievements + challenges;
      });

  /// Nur Profile, Ziele, Trainingspläne, Erfolge und Challenge-Ergebnisse
  /// (aus einem Manifest).
  Future<MergeResult> mergeMeta(SyncManifest m) => db.transaction(() async {
        final players = await _mergePlayers(m.players);
        final goals = await _mergeGoals(m.goals, players);
        final plans = await _mergePlans(m.plans);
        final achievements = await _mergeAchievements(m.achievements, players);
        final challenges = await _mergeChallenges(m.challenges, players);
        return players.result + goals + plans + achievements + challenges;
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
    await (db.delete(db.achievements)..where((a) => a.playerId.equals(id))).go();
    await (db.delete(db.challengeResults)..where((c) => c.playerId.equals(id))).go();
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

  /// Eigene Trainingspläne: neueste Änderung gewinnt, Löschmarkierungen
  /// werden übernommen und weitergegeben. Bei gleicher Zeit gewinnt das
  /// Löschen, sonst der größere Inhalt (Name, Beschreibung, Schritte), damit
  /// beide Seiten dasselbe Ergebnis haben.
  Future<MergeResult> _mergePlans(List<Map<String, Object?>> incoming) async {
    var created = 0;
    var updated = 0;
    for (final j in incoming) {
      final uid = j['uid'];
      final rawName = j['name'];
      final stepsJson = j['stepsJson'];
      if (uid is! String || uid.isEmpty || rawName is! String || stepsJson is! String) continue;
      var name = rawName.trim();
      if (name.length > 60) name = name.substring(0, 60);
      if (name.isEmpty) continue;
      final description = j['description'] as String? ?? '';
      final createdAt = _parse(j['createdAt']) ?? DateTime.now();
      final updatedAt = _parse(j['updatedAt']);
      final deletedAt = _parse(j['deletedAt']);

      final local = await (db.select(db.trainingPlans)..where((p) => p.uid.equals(uid))).getSingleOrNull();
      if (local == null) {
        await db.into(db.trainingPlans).insert(TrainingPlansCompanion.insert(
              uid: Value(uid),
              name: name,
              description: Value(description),
              stepsJson: stepsJson,
              createdAt: createdAt,
              updatedAt: Value(updatedAt),
              deletedAt: Value(deletedAt),
            ));
        if (deletedAt == null) created++;
        continue;
      }
      final theirs = _stamp(createdAt, updatedAt);
      final theirDeleted = deletedAt != null;
      final ourDeleted = local.deletedAt != null;
      final theirContent = [name, description, stepsJson].join('\n');
      final ourContent = [local.name, local.description, local.stepsJson].join('\n');
      final differs = theirContent != ourContent || theirDeleted != ourDeleted;
      final tie = theirDeleted != ourDeleted ? (theirDeleted ? 1 : -1) : theirContent.compareTo(ourContent);
      if (differs && _newer(theirs, _stamp(local.createdAt, local.updatedAt), tie)) {
        await (db.update(db.trainingPlans)..where((p) => p.id.equals(local.id))).write(TrainingPlansCompanion(
          name: Value(name),
          description: Value(description),
          stepsJson: Value(stepsJson),
          updatedAt: Value(theirs),
          deletedAt: Value(deletedAt),
        ));
        updated++;
      }
    }
    return MergeResult(plans: created, updated: updated);
  }

  /// Erfolgs-Stufen: fehlende übernehmen, bei vorhandenen gilt das frühere
  /// Datum.
  Future<MergeResult> _mergeAchievements(List<Map<String, Object?>> incoming, _PlayerMap players) async {
    var created = 0;
    var updated = 0;
    for (final j in incoming) {
      final player = await players.resolve(this, j);
      if (player == null || player.deleted) continue;
      final id = j['achievementId'];
      final tier = j['tier'];
      final at = _parse(j['unlockedAt']);
      if (id is! String || id.isEmpty || tier is! num || at == null) continue;
      final local = await (db.select(db.achievements)
            ..where((a) => a.playerId.equals(player.id) & a.achievementId.equals(id) & a.tier.equals(tier.toInt())))
          .getSingleOrNull();
      if (local == null) {
        await db.into(db.achievements).insert(AchievementsCompanion.insert(
              playerId: player.id,
              achievementId: id,
              tier: tier.toInt(),
              unlockedAt: at,
            ));
        created++;
      } else if (at.isBefore(local.unlockedAt)) {
        await (db.update(db.achievements)..where((a) => a.id.equals(local.id)))
            .write(AchievementsCompanion(unlockedAt: Value(at)));
        updated++;
      }
    }
    return MergeResult(achievements: created, updated: updated);
  }

  /// Challenge-Ergebnisse: Sterne, Bestwert und Versuche jeweils das Bessere.
  /// Das Datum gehört zum besseren Ergebnis, bei Gleichstand das frühere.
  Future<MergeResult> _mergeChallenges(List<Map<String, Object?>> incoming, _PlayerMap players) async {
    var changed = 0;
    for (final j in incoming) {
      final player = await players.resolve(this, j);
      if (player == null || player.deleted) continue;
      final id = j['challengeId'];
      final rawStars = j['stars'];
      if (id is! String || id.isEmpty || rawStars is! num) continue;
      final stars = rawStars.toInt().clamp(0, 3);
      final best = (j['best'] as num?)?.toDouble();
      final attempts = (j['attempts'] as num?)?.toInt() ?? 0;
      final achievedAt = _parse(j['achievedAt']) ?? DateTime.now();
      final updatedAt = _parse(j['updatedAt']) ?? achievedAt;
      final local = await (db.select(db.challengeResults)
            ..where((c) => c.playerId.equals(player.id) & c.challengeId.equals(id)))
          .getSingleOrNull();
      if (local == null) {
        await db.into(db.challengeResults).insert(ChallengeResultsCompanion.insert(
              playerId: player.id,
              challengeId: id,
              stars: Value(stars),
              best: Value(best),
              attempts: Value(attempts),
              achievedAt: achievedAt,
              updatedAt: updatedAt,
            ));
        changed++;
        continue;
      }
      final lower = ChallengeCatalog.byId(id)?.lowerIsBetter ?? false;
      final localBest = local.best;
      final theirBestBetter = best != null && (localBest == null || (lower ? best < localBest : best > localBest));
      final theirStarsBetter = stars > local.stars;
      final theirsBetter = theirStarsBetter || (stars == local.stars && theirBestBetter);
      final same = stars == local.stars && best == localBest;
      final next = (
        stars: theirStarsBetter ? stars : local.stars,
        best: theirBestBetter ? best : localBest,
        attempts: attempts > local.attempts ? attempts : local.attempts,
        achievedAt: theirsBetter || (same && achievedAt.isBefore(local.achievedAt)) ? achievedAt : local.achievedAt,
        updatedAt: updatedAt.isAfter(local.updatedAt) ? updatedAt : local.updatedAt,
      );
      if (next.stars == local.stars &&
          next.best == localBest &&
          next.attempts == local.attempts &&
          next.achievedAt == local.achievedAt &&
          next.updatedAt == local.updatedAt) {
        continue;
      }
      await (db.update(db.challengeResults)..where((c) => c.id.equals(local.id))).write(ChallengeResultsCompanion(
        stars: Value(next.stars),
        best: Value(next.best),
        attempts: Value(next.attempts),
        achievedAt: Value(next.achievedAt),
        updatedAt: Value(next.updatedAt),
      ));
      changed++;
    }
    return MergeResult(challenges: changed);
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
