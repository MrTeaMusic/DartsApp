import 'dart:convert';

import '../../games/domain/engine/game_definition.dart';
import '../../games/domain/game_catalog.dart';

/// Ein Schritt eines Trainingsplans: ein Spiel mit seiner Config und einem
/// optionalen Hinweis.
class PlanStep {
  const PlanStep({required this.gameId, this.config = const {}, this.note});

  /// Kennung aus dem [GameCatalog]. Unbekannte Kennungen (Spiel aus einer
  /// neueren App-Version) bleiben erhalten und gelten als nicht verfügbar.
  final String gameId;

  /// Config wie von [GameDefinition.resolve] akzeptiert. Fehlende Werte
  /// kommen beim Start aus den Standardwerten des Spiels.
  final Map<String, Object?> config;
  final String? note;

  GameDefinition? get definition => GameCatalog.byId(gameId);
  bool get available => definition != null;

  /// Config mit Standardwerten; bei unbekanntem Spiel unverändert.
  Map<String, Object?> get resolvedConfig => definition?.resolve(config) ?? config;

  PlanStep copyWith({String? gameId, Map<String, Object?>? config, String? note, bool clearNote = false}) => PlanStep(
        gameId: gameId ?? this.gameId,
        config: config ?? this.config,
        note: clearNote ? null : (note ?? this.note),
      );

  Map<String, Object?> toJson() => {
        'gameId': gameId,
        'config': config,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  /// `null` bei unbrauchbaren Einträgen.
  static PlanStep? fromJson(Object? j) {
    if (j is! Map) return null;
    final gameId = j['gameId'];
    if (gameId is! String || gameId.isEmpty) return null;
    final config = j['config'];
    final note = j['note'];
    return PlanStep(
      gameId: gameId,
      config: config is Map ? Map<String, Object?>.from(config) : const {},
      note: note is String && note.isNotEmpty ? note : null,
    );
  }

  static String encodeList(List<PlanStep> steps) => jsonEncode([for (final s in steps) s.toJson()]);

  static List<PlanStep> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final v = jsonDecode(json);
      if (v is! List) return const [];
      return [for (final e in v) ?PlanStep.fromJson(e)];
    } on FormatException {
      return const [];
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlanStep && other.gameId == gameId && other.note == note && jsonEncode(other.config) == jsonEncode(config);

  @override
  int get hashCode => Object.hash(gameId, note, jsonEncode(config));
}

/// Ein Trainingsplan: geordnete Liste von [PlanStep]s.
///
/// Feste Pläne stehen im Code (`builtin_plans.dart`, IDs mit `builtin-`),
/// eigene in der Datenbank (ID = `uid` der Zeile).
class TrainingPlan {
  const TrainingPlan({
    required this.id,
    required this.name,
    this.description = '',
    required this.steps,
    this.builtIn = false,
  });

  static const String builtinPrefix = 'builtin-';
  static const int maxNameLength = 60;
  static const int maxDescriptionLength = 400;

  final String id;
  final String name;
  final String description;
  final List<PlanStep> steps;
  final bool builtIn;

  /// Schritte, deren Spiel es in dieser App-Version gibt.
  int get availableSteps => steps.where((s) => s.available).length;

  /// Kann gestartet werden (mindestens ein spielbarer Schritt).
  bool get playable => availableSteps > 0;

  static bool isBuiltinId(String id) => id.startsWith(builtinPrefix);

  /// Name gekürzt und ohne Leerzeichen am Rand.
  static String cleanName(String name) {
    final t = name.trim();
    return t.length > maxNameLength ? t.substring(0, maxNameLength) : t;
  }

  static String cleanDescription(String text) {
    final t = text.trim();
    return t.length > maxDescriptionLength ? t.substring(0, maxDescriptionLength) : t;
  }
}

/// Status eines Schritts in einem Plan-Durchlauf.
enum StepStatus {
  /// Regulär zu Ende gespielt.
  done,

  /// Vorzeitig beendet und weitergegangen.
  aborted,

  /// Spiel gibt es in dieser App-Version nicht.
  unavailable;

  static StepStatus byName(Object? name) => values.firstWhere((v) => v.name == name, orElse: () => aborted);
}

/// Ergebnis eines Schritts im Durchlauf, mit den Zeilen des Ergebnis-
/// Bildschirms (damit die Zusammenfassung ohne Neuberechnung auskommt).
class StepResult {
  const StepResult({required this.step, required this.status, this.sessionUid, this.summary = const [], this.darts = 0});

  /// Index des Schritts im Plan.
  final int step;
  final StepStatus status;
  final String? sessionUid;

  /// Schlüssel/Wert-Paare wie `GameStat`.
  final List<(String, String)> summary;
  final int darts;

  Map<String, Object?> toJson() => {
        'step': step,
        'status': status.name,
        'sessionUid': ?sessionUid,
        'darts': darts,
        'summary': [for (final (k, v) in summary) {'key': k, 'value': v}],
      };

  static StepResult? fromJson(Object? j) {
    if (j is! Map || j['step'] is! num) return null;
    final summary = j['summary'];
    return StepResult(
      step: (j['step'] as num).toInt(),
      status: StepStatus.byName(j['status']),
      sessionUid: j['sessionUid'] as String?,
      darts: (j['darts'] as num?)?.toInt() ?? 0,
      summary: [
        if (summary is List)
          for (final e in summary)
            if (e is Map && e['key'] is String && e['value'] is String) (e['key'] as String, e['value'] as String),
      ],
    );
  }

  static String encodeList(List<StepResult> results) => jsonEncode([for (final r in results) r.toJson()]);

  static List<StepResult> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final v = jsonDecode(json);
      return v is List ? [for (final e in v) ?StepResult.fromJson(e)] : const [];
    } on FormatException {
      return const [];
    }
  }
}

/// Ein Durchlauf eines Plans für ein Profil. Die Schritte sind beim Start
/// eingefroren, damit spätere Änderungen am Plan einen angefangenen
/// Durchlauf nicht durcheinanderbringen.
class PlanRun {
  const PlanRun({
    required this.id,
    required this.uid,
    required this.planId,
    required this.planName,
    required this.steps,
    required this.playerId,
    required this.startedAt,
    this.finishedAt,
    this.currentStep = 0,
    this.results = const [],
  });

  final int id;
  final String uid;
  final String planId;
  final String planName;
  final List<PlanStep> steps;
  final int playerId;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// Index des nächsten zu spielenden Schritts; `== steps.length`, wenn alle
  /// erledigt sind.
  final int currentStep;
  final List<StepResult> results;

  bool get finished => finishedAt != null;
  bool get allStepsDone => currentStep >= steps.length;
  StepResult? resultOf(int step) => results.where((r) => r.step == step).lastOrNull;
}
