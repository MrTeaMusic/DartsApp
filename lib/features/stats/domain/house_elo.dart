/// Haus-Elo: eine eigene Elo-Wertung für die Matches des aktiven Profils,
/// ganz neu berechnet aus den abgeschlossenen Match-Sessions. Reine Dart-
/// Logik ohne Datenbank und Flutter; die Erklärung für Laien steht in
/// `docs/haus-elo.md`.
///
/// * [EloMatch.fromSession] ist die **einzige Stelle**, die entscheidet, ob
///   eine Session als gewertetes Match zählt und wer der Gegner war.
/// * [HouseElo.compute] rechnet alle Matches in Zeitreihenfolge. Es wird
///   nichts gespeichert: Löschen, Nachimport und Abgleich ändern die Sessions,
///   und der nächste Lauf ergibt wieder ein stimmiges Ergebnis.
library;

import 'dart:math' as math;

import '../../autodarts_live/domain/live_stats.dart' show autodartsLiveX01GameId;
import '../../matches/domain/match_result.dart' show matchGameId;
import 'stats_models.dart';

/// Woher ein Gegner kommt.
enum EloOpponentKind {
  /// Gegner aus dem Autodarts-Konto (Import).
  online,

  /// Computergegner.
  bot,

  /// Mitspieler am selben Board (Profil oder Gast).
  local,
}

/// Konstanten der Rechnung (alles an einer Stelle).
abstract final class HouseEloRules {
  /// Startwert: nur ein Skalenanker, die absolute Zahl bedeutet nichts.
  static const double start = 1000;

  /// Je 400 Punkte Unterschied gewinnt der Stärkere zehnmal so oft.
  static const double scale = 400;

  /// Änderungsstärke K für Ben in den ersten [earlyMatches] Matches, danach
  /// [kLater]. Und für den Gegner immer [kOpponent].
  static const double kEarly = 32;
  static const double kLater = 24;
  static const double kOpponent = 24;
  static const int earlyMatches = 20;

  /// Schätzung eines neuen Gegners: Elo-Punkte je Average-Punkt Unterschied
  /// und die größte erlaubte Abweichung von Bens Wert.
  static const double pointsPerAverage = 12;
  static const double maxEstimateOffset = 300;

  /// Aus den letzten so vielen gewerteten Matches kommt Bens gleitender
  /// Average für die Schätzung.
  static const int averageWindow = 10;

  /// Ab so vielen gewerteten Matches zeigt die Oberfläche den Verlauf.
  static const int minMatchesForChart = 3;
}

/// Ein gewertetes Match aus Sicht des aktiven Profils.
class EloMatch {
  const EloMatch({
    required this.sessionId,
    required this.sortKey,
    required this.at,
    required this.kind,
    required this.opponentId,
    required this.opponentName,
    required this.won,
    this.myAverage,
    this.opponentAverage,
    this.botAverage,
    this.legsWon,
    this.legsLost,
  });

  final int sessionId;

  /// Stabiler Tie-Breaker bei gleicher Startzeit (die Session-Uid, auf jedem
  /// Gerät gleich; die lokale Id wäre es nicht).
  final String sortKey;
  final DateTime at;
  final EloOpponentKind kind;

  /// Stabile Kennung des Gegners: `online:<name>`, `bot:<name>@<average>`,
  /// `local:<name>` (alles klein geschrieben).
  final String opponentId;
  final String opponentName;
  final bool won;

  /// 3-Dart-Average des Profils in diesem Match.
  final double? myAverage;

  /// Average des Gegners für die Schätzung: bei Bots der nominale Average,
  /// sonst der im Match erzielte.
  final double? opponentAverage;

  /// Nominaler Average eines Bots (zur Anzeige der Stufe).
  final double? botAverage;
  final int? legsWon;
  final int? legsLost;

  /// Reihenfolge: Startzeit, bei Gleichstand Uid, dann lokale Id.
  static int compare(EloMatch a, EloMatch b) {
    final t = a.at.millisecondsSinceEpoch.compareTo(b.at.millisecondsSinceEpoch);
    if (t != 0) return t;
    final k = a.sortKey.compareTo(b.sortKey);
    return k != 0 ? k : a.sessionId.compareTo(b.sessionId);
  }

  /// Zählt eine Session als gewertetes Match? Die Regel, an einer Stelle:
  ///
  /// * Spiel `x01_match` (Bot, Mitspieler, Turnier) oder ein **importiertes**
  ///   Online-Match (`x01_live` mit `import`). Training, Solo, Quiz und
  ///   mitgeschriebene Live-Sessions ohne Gegner zählen nie.
  /// * Die Session ist regulär zu Ende gespielt (`finished`), also nicht
  ///   abgebrochen.
  /// * Der Ausgang ist bekannt (kennzahl `won`, sonst `details.won`). Ein
  ///   importiertes Match ohne Sieger (Gleichstand, offen) hat keinen.
  /// * Es gibt genau einen Gegner.
  ///
  /// [result] ist das dekodierte `result_json`, [config] das dekodierte
  /// `config_json`. Liefert `null`, wenn die Session nicht zählt.
  static EloMatch? fromSession({
    required int sessionId,
    required String uid,
    required String gameId,
    required DateTime startedAt,
    required bool finished,
    required Map<String, Object?> config,
    required Map<String, Object?> result,
  }) {
    if (!finished) return null;
    if (gameId != matchGameId && gameId != autodartsLiveX01GameId) return null;
    final details = result['details'] is Map ? Map<String, Object?>.from(result['details'] as Map) : const <String, Object?>{};
    final imported = config['import'] is Map || details['import'] is Map;
    if (gameId == autodartsLiveX01GameId && !imported) return null;

    final metrics = result['metrics'] is Map ? result['metrics'] as Map<Object?, Object?> : const <Object?, Object?>{};
    if (metrics['completed'] == 0) return null;
    final bool? won = switch ((metrics['won'], details['won'])) {
      (final num w, _) => w == 1,
      (_, final bool w) => w,
      _ => null,
    };
    if (won == null) return null;

    // Gegner: die Teilnehmerliste des Ergebnisses; ältere Matches kennen nur
    // die Namen.
    final rawPlayers = details['players'] is List ? details['players'] as List : const [];
    final meIndex = details['player'] is num ? (details['player'] as num).toInt() : 0;
    Map<Object?, Object?>? me;
    Map<Object?, Object?>? opp;
    if (rawPlayers.length == 2 && (meIndex == 0 || meIndex == 1)) {
      me = rawPlayers[meIndex] is Map ? rawPlayers[meIndex] as Map<Object?, Object?> : null;
      opp = rawPlayers[1 - meIndex] is Map ? rawPlayers[1 - meIndex] as Map<Object?, Object?> : null;
    }
    final rawNames = details['opponents'] ?? config['opponents'];
    final names = rawNames is List ? rawNames : const [];
    String name;
    if (opp != null && opp['name'] is String) {
      name = opp['name'] as String;
    } else if (names.length == 1) {
      name = '${names.first}';
    } else {
      return null;
    }
    name = name.trim().isEmpty ? '?' : name.trim();
    final lower = name.toLowerCase();

    double? positive(Object? v) => v is num && v > 0 ? v.toDouble() : null;
    final myAverage = positive(metrics['average']) ?? positive(me?['average']);
    final nominal = positive(opp?['botAverage']);
    final measured = positive(opp?['average']);

    final EloOpponentKind kind;
    final String id;
    final double? opponentAverage;
    if (imported) {
      kind = EloOpponentKind.online;
      id = 'online:$lower';
      opponentAverage = measured;
    } else if (opp?['bot'] == true || (opp == null && config['vsBot'] == true)) {
      kind = EloOpponentKind.bot;
      id = nominal == null ? 'bot:$lower' : 'bot:$lower@${nominal.round()}';
      opponentAverage = nominal ?? measured;
    } else {
      kind = EloOpponentKind.local;
      id = 'local:$lower';
      opponentAverage = measured;
    }
    return EloMatch(
      sessionId: sessionId,
      sortKey: uid,
      at: startedAt,
      kind: kind,
      opponentId: id,
      opponentName: name,
      won: won,
      myAverage: myAverage,
      opponentAverage: opponentAverage,
      botAverage: kind == EloOpponentKind.bot ? nominal : null,
      legsWon: metrics['legsWon'] is num ? (metrics['legsWon'] as num).toInt() : null,
      legsLost: metrics['legsLost'] is num ? (metrics['legsLost'] as num).toInt() : null,
    );
  }
}

/// Ein gewertetes Match mit den Ratings davor und danach.
class EloStep {
  const EloStep({
    required this.match,
    required this.number,
    required this.before,
    required this.after,
    required this.expected,
    required this.k,
    required this.opponentBefore,
    required this.opponentAfter,
    required this.opponentEstimated,
  });

  final EloMatch match;

  /// Laufende Nummer ab 1.
  final int number;
  final double before;
  final double after;

  /// Erwartete Siegchance (0–1) vor dem Match.
  final double expected;
  final double k;

  /// Haus-Rating des Gegners vor und nach dem Match.
  final double opponentBefore;
  final double opponentAfter;

  /// Der Gegner trat zum ersten Mal auf: sein Rating war geschätzt.
  final bool opponentEstimated;

  double get change => after - before;
  DateTime get at => match.at;
  int get sessionId => match.sessionId;
  bool get won => match.won;
}

/// Ein Gegner mit seiner Bilanz (über alle Matches oder einen Zeitraum).
class EloOpponent {
  const EloOpponent({
    required this.id,
    required this.name,
    required this.kind,
    required this.matches,
    required this.wins,
    required this.losses,
    required this.rating,
    required this.change,
    required this.lastAt,
    this.botAverage,
  });

  final String id;
  final String name;
  final EloOpponentKind kind;
  final int matches;
  final int wins;
  final int losses;

  /// Haus-Rating des Gegners nach dem letzten Match der Auswahl.
  final double rating;

  /// Summe der Elo-Änderungen des Profils gegen diesen Gegner.
  final double change;
  final DateTime lastAt;
  final double? botAverage;
}

/// Ergebnis der Rechnung: alle Schritte in Zeitreihenfolge und Kennzahlen.
class HouseEloReport {
  HouseEloReport(this.steps);

  static final HouseEloReport empty = HouseEloReport(const []);

  /// Gewertete Matches, älteste zuerst.
  final List<EloStep> steps;

  bool get isEmpty => steps.isEmpty;
  int get matches => steps.length;

  /// Genug Matches für einen Verlauf.
  bool get hasHistory => steps.length >= HouseEloRules.minMatchesForChart;

  /// Aktuelles Elo ([HouseEloRules.start] ohne Matches).
  double get current => steps.isEmpty ? HouseEloRules.start : steps.last.after;

  /// Höchster Stand nach einem Match (mit Datum); `null` ohne Matches.
  EloStep? get peakStep {
    EloStep? best;
    for (final s in steps) {
      if (best == null || s.after > best.after) best = s;
    }
    return best;
  }

  double? get peak => peakStep?.after;
  int get wins => steps.where((s) => s.won).length;
  int get losses => steps.length - wins;

  int count(EloOpponentKind kind) => steps.where((s) => s.match.kind == kind).length;

  /// Stand vor [from]: Rating nach dem letzten Match davor, sonst der Start.
  double ratingBefore(DateTime from) {
    var r = HouseEloRules.start;
    for (final s in steps) {
      if (!s.at.isBefore(from)) break;
      r = s.after;
    }
    return r;
  }

  /// Veränderung seit [from]: aktuelles Elo minus Stand vor [from].
  double changeSince(DateTime from) => current - ratingBefore(from);

  /// Schritte ab [from] (`null` = alle).
  List<EloStep> stepsFrom(DateTime? from) =>
      from == null ? steps : [for (final s in steps) if (!s.at.isBefore(from)) s];

  /// Verlauf für das Diagramm: Stand nach jedem Match ab [from].
  List<TrendPoint> trend(DateTime? from) =>
      [for (final s in stepsFrom(from)) TrendPoint(s.sessionId, s.at, s.after)];

  /// Gegner mit Bilanz, die meisten Matches zuerst. Zählt nur Matches ab
  /// [from]; [kind] schränkt auf eine Art ein.
  List<EloOpponent> opponents({DateTime? from, EloOpponentKind? kind}) {
    final byId = <String, List<EloStep>>{};
    for (final s in stepsFrom(from)) {
      if (kind != null && s.match.kind != kind) continue;
      byId.putIfAbsent(s.match.opponentId, () => []).add(s);
    }
    final out = [
      for (final e in byId.entries)
        EloOpponent(
          id: e.key,
          name: e.value.last.match.opponentName,
          kind: e.value.last.match.kind,
          matches: e.value.length,
          wins: e.value.where((s) => s.won).length,
          losses: e.value.where((s) => !s.won).length,
          rating: e.value.last.opponentAfter,
          change: e.value.fold(0.0, (a, s) => a + s.change),
          lastAt: e.value.last.at,
          botAverage: e.value.last.match.botAverage,
        ),
    ];
    out.sort((a, b) {
      final m = b.matches.compareTo(a.matches);
      if (m != 0) return m;
      final t = b.lastAt.compareTo(a.lastAt);
      return t != 0 ? t : a.name.compareTo(b.name);
    });
    return out;
  }

  /// Größte Siege: besiegte Gegner mit dem höchsten Rating (vor dem Match).
  List<EloStep> bestWins({DateTime? from, int count = 3}) => _ranked(from, won: true, count: count);

  /// Bitterste Niederlagen: verloren gegen Gegner mit dem niedrigsten Rating.
  List<EloStep> worstLosses({DateTime? from, int count = 3}) => _ranked(from, won: false, count: count);

  List<EloStep> _ranked(DateTime? from, {required bool won, required int count}) {
    final list = [for (final s in stepsFrom(from)) if (s.won == won) s];
    list.sort((a, b) {
      final r = won ? b.opponentBefore.compareTo(a.opponentBefore) : a.opponentBefore.compareTo(b.opponentBefore);
      return r != 0 ? r : b.at.compareTo(a.at);
    });
    return list.take(count).toList();
  }

  /// Schritt zu einer Session (für die Zeile im Spielverlauf).
  EloStep? stepOf(int sessionId) {
    for (final s in steps) {
      if (s.sessionId == sessionId) return s;
    }
    return null;
  }
}

/// Die Rechnung selbst.
abstract final class HouseElo {
  /// Erwartete Siegchance von [rating] gegen [opponent].
  static double expected(double rating, double opponent) =>
      1 / (1 + math.pow(10, (opponent - rating) / HouseEloRules.scale));

  /// K für das [index]-te Match (ab 0).
  static double kFor(int index) => index < HouseEloRules.earlyMatches ? HouseEloRules.kEarly : HouseEloRules.kLater;

  /// Rating eines neuen Gegners: Bens Rating plus 12 Punkte je Average-Punkt
  /// Unterschied, höchstens ±300. Fehlt ein Average, startet der Gegner bei
  /// Bens Rating.
  static double estimate({required double myRating, double? opponentAverage, double? myAverage}) {
    if (opponentAverage == null || myAverage == null) return myRating;
    final offset = HouseEloRules.pointsPerAverage * (opponentAverage - myAverage);
    return myRating + offset.clamp(-HouseEloRules.maxEstimateOffset, HouseEloRules.maxEstimateOffset);
  }

  /// Rechnet alle Matches in Zeitreihenfolge. Die Reihenfolge der Eingabe ist
  /// egal: Sortiert wird nach Startzeit und Uid.
  static HouseEloReport compute(Iterable<EloMatch> input) {
    final matches = input.toList()..sort(EloMatch.compare);
    if (matches.isEmpty) return HouseEloReport.empty;
    final opponents = <String, double>{};
    final recent = <double>[];
    final steps = <EloStep>[];
    var rating = HouseEloRules.start;
    for (final (i, m) in matches.indexed) {
      // Bens gleitender Average aus den Matches davor; im ersten Match der
      // Average dieses Matches.
      final mine = recent.isEmpty ? m.myAverage : recent.reduce((a, b) => a + b) / recent.length;
      final known = opponents[m.opponentId];
      final opponentBefore = known ?? estimate(myRating: rating, opponentAverage: m.opponentAverage, myAverage: mine);
      final e = expected(rating, opponentBefore);
      final s = m.won ? 1.0 : 0.0;
      final k = kFor(i);
      final after = rating + k * (s - e);
      // Der Gegner verliert, was Ben gewinnt (mit seinem eigenen K).
      final opponentAfter = opponentBefore + HouseEloRules.kOpponent * (e - s);
      steps.add(EloStep(
        match: m,
        number: i + 1,
        before: rating,
        after: after,
        expected: e,
        k: k,
        opponentBefore: opponentBefore,
        opponentAfter: opponentAfter,
        opponentEstimated: known == null,
      ));
      opponents[m.opponentId] = opponentAfter;
      rating = after;
      if (m.myAverage != null) {
        recent.add(m.myAverage!);
        if (recent.length > HouseEloRules.averageWindow) recent.removeAt(0);
      }
    }
    return HouseEloReport(steps);
  }
}
