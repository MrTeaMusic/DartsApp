import '../domain/autodarts_match_mapping.dart';
import '../domain/imported_match.dart';
import '../domain/import_plan.dart';
import 'autodarts_import_repository.dart';

/// Was aus einer Anfrage zum Import geworden ist.
enum ImportStatus {
  imported,
  duplicate,

  /// Kein X01-Match (oder sonst nichts zu tun): bewusst nicht gespeichert.
  ignored,

  /// Das Match ist lesbar, aber DartLab weiß nicht, welcher der beiden
  /// Spieler man selbst ist. Es wartet auf die Antwort in der App.
  pending,
}

/// Antwort des Imports, für Empfänger, Dialog und Statuszeile.
class ImportReply {
  const ImportReply(
    this.status, {
    this.id,
    this.message,
    this.plan,
    this.match,
    this.sessionId,
    this.replaced = false,
    this.overlapStartedAt,
  });

  final ImportStatus status;

  /// Autodarts-Match-Id.
  final String? id;

  /// Hinweis bei „ignored“ (z. B. „Kein X01-Match (Variante: Cricket).“).
  final String? message;
  final ImportPlan? plan;

  /// Bei „pending“ das gelesene Match.
  final ImportedMatch? match;
  final int? sessionId;
  final bool replaced;

  /// Beginn einer überschneidenden Live-Aufzeichnung (zählt doppelt).
  final DateTime? overlapStartedAt;

  String? get opponent => plan?.opponent.name;
}

/// Liest, erkennt, rechnet und speichert ein Match. Reine Logik ohne
/// Oberfläche; Empfänger, Dialog und Tests nutzen dieselbe Stelle.
class AutodartsImportService {
  AutodartsImportService({
    required this.repository,
    required this.playerId,
    required this.myName,
    required this.rememberName,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AutodartsImportRepository repository;

  /// Profil, dem das Match gehört.
  final Future<int> Function() playerId;

  /// Eingestellter „Mein Autodarts-Name“.
  final String Function() myName;

  /// Merkt sich den Namen, den man in der Frage „Welcher Spieler bist du?“
  /// gewählt hat.
  final Future<void> Function(String name) rememberName;
  final DateTime Function() _clock;

  /// Liest das Match (wirft [AutodartsImportException]).
  ImportedMatch read(Object? json, {String? externalId}) => parseAutodartsMatch(json, externalId: externalId);

  /// Importiert [json]. [me] ist der Index des eigenen Spielers, wenn man ihn
  /// gewählt hat (wird dann als Name gemerkt); sonst erkennt der Service ihn
  /// am eingestellten Namen. Nicht X01 → „ignored“, sonstige Probleme als
  /// [AutodartsImportException].
  Future<ImportReply> importJson(
    Object? json, {
    String? externalId,
    int? me,
    String origin = 'file',
    bool replace = false,
  }) async {
    final ImportedMatch match;
    try {
      match = read(json, externalId: externalId);
    } on AutodartsImportException catch (e) {
      if (e.problem == ImportProblem.notX01) return ImportReply(ImportStatus.ignored, message: e.message);
      rethrow;
    }
    return importMatch(match, me: me, origin: origin, replace: replace);
  }

  Future<ImportReply> importMatch(ImportedMatch match, {int? me, String origin = 'file', bool replace = false}) async {
    final chosen = me ?? identifyMe(match, myName());
    if (chosen == null) {
      // Schon importiert? Dann ist die Frage unnötig.
      final existing = await repository.findByMatchId(match.id);
      if (existing != null && !replace) {
        return ImportReply(ImportStatus.duplicate, id: match.id, sessionId: existing.id, match: match);
      }
      return ImportReply(ImportStatus.pending, id: match.id, match: match);
    }
    final plan = buildImportPlan(match, me: chosen, now: _clock(), origin: origin);
    // Ein unfertiges Match (Stand mitten im Spiel) macht Platz für das fertige.
    var doReplace = replace;
    if (!doReplace && plan.finished) {
      final existing = await repository.findByMatchId(match.id);
      doReplace = existing != null && !existing.finished;
    }
    final saved = await repository.save(plan, playerId: await playerId(), replace: doReplace);
    if (me != null && myName().trim().toLowerCase() != plan.myPlayer.name.trim().toLowerCase()) {
      await rememberName(plan.myPlayer.name);
    }
    return ImportReply(
      saved.status == ImportSaveStatus.duplicate ? ImportStatus.duplicate : ImportStatus.imported,
      id: match.id,
      plan: plan,
      match: match,
      sessionId: saved.sessionId,
      replaced: saved.status == ImportSaveStatus.replaced,
      overlapStartedAt: saved.overlap?.startedAt,
    );
  }
}
