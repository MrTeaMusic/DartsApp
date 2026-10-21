/// Wurftempo: wie schnell wirft jemand, aus den Zeitstempeln der Würfe.
///
/// Die Regeln stehen in `docs/wurftempo.md`. Kurz:
///
/// * **Wurfabstand**: Zeit zwischen zwei Darts derselben Aufnahme.
/// * **Aufnahmezeit**: erster bis dritter Dart einer vollen Aufnahme.
/// * **Zeit mit Takeout**: erster Dart einer Aufnahme bis erster Dart der
///   nächsten (nur im Training, wo niemand sonst wirft).
/// * Es zählen nur Darts, deren Zeit vom Board kommt (Quelle Autodarts) und
///   die nicht nachträglich entstanden sind. Eine Aufnahme mit einem
///   unsicheren Dart fällt ganz heraus.
/// * Immer der Median, nie der Mittelwert.
library;

import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../../dart_source/domain/dart_event.dart' show DartSourceKind, DartThrow;
import '../../matches/domain/match_result.dart' show matchGameId;
import 'game_metrics.dart';
import 'online_stats.dart';

/// Wo geworfen wurde: im Training wirft nur man selbst, im Match und bei
/// Online-Matches warten die Aufnahmen auf den Gegner.
enum TempoGroup {
  training,
  match,
  live;

  static TempoGroup of(String gameId) => gameId == matchGameId
      ? match
      : isOnlineGame(gameId)
      ? live
      : training;
}

/// Tempoklassen einer vollen Aufnahme (erster bis dritter Dart).
enum TempoBand {
  fast,
  medium,
  slow;

  static TempoBand of(double seconds) => seconds < TempoRules.fastLimit
      ? fast
      : seconds <= TempoRules.slowLimit
      ? medium
      : slow;
}

/// Ein Dart für die Zeitrechnung: wann und ob die Zeit verlässlich ist.
typedef TimedDart = ({DateTime time, bool timed});

/// Alle Grenzwerte an einer Stelle.
abstract final class TempoRules {
  /// Kürzerer Abstand zweier Darts ist kein echter Wurf (zwei Darts mit
  /// derselben Zeit: von Hand ergänzt, gebündelt eingespielt).
  static const double minGap = 0.5;

  /// Längerer Abstand ist eine Pause, keine Wurfzeit (Telefon, Getränk,
  /// Streit mit dem Gegner). Gilt für Wurfabstände und die Zeit mit Takeout.
  static const double maxPause = 60;

  /// So weit darf ein Wurf vor dem Beginn seiner Session liegen, bevor er als
  /// nachträglich gilt (Uhren gehen nicht auf die Millisekunde gleich).
  static const Duration beforeStart = Duration(seconds: 5);

  /// Ab so vielen Messwerten zeigt die Statistik eine Zahl, sonst „zu wenig
  /// Daten“. Gilt je Kennzahl, je Woche im Verlauf und je Tempoklasse.
  static const int minSamples = 10;

  /// Wochen im Verlauf.
  static const int trendWeeks = 12;

  /// Grenzen der Tempoklassen in Sekunden: unter [fastLimit] schnell, bis
  /// [slowLimit] mittel, darüber langsam.
  static const double fastLimit = 6;
  static const double slowLimit = 12;

  /// Nur Darts vom Board haben eine Zeit, die das Werfen misst. Beim
  /// Simulator misst sie das Klicken, bei der manuellen Eingabe das Tippen.
  static final String timedSource = DartSourceKind.autodartsLocal.name;

  /// Verlässliche Zeit eines gespeicherten Wurfs: vom Board und nicht vor dem
  /// Beginn der Session (fortgesetztes Match, nachträglich eingespielt).
  static bool isTimedRow(ThrowRow t, DateTime sessionStart) =>
      t.source == timedSource && !t.timestamp.isBefore(sessionStart.subtract(beforeStart));

  /// Abstände (Sekunden) zwischen den Darts einer Aufnahme; `null`, wenn die
  /// Aufnahme nicht verlässlich ist: ein Dart ohne echte Zeit, ein Abstand
  /// unter [minGap] (auch rückwärts) oder über [maxPause]. Eine Aufnahme mit
  /// einem Dart hat keine Abstände (leere Liste).
  static List<double>? gapsOf(List<TimedDart> visit) {
    if (visit.isEmpty || visit.any((d) => !d.timed)) return null;
    final gaps = <double>[];
    for (var i = 1; i < visit.length; i++) {
      final g = visit[i].time.difference(visit[i - 1].time).inMilliseconds / 1000;
      if (g < minGap || g > maxPause) return null;
      gaps.add(g);
    }
    return gaps;
  }

  /// Median; `null` ohne Werte.
  ///
  /// Die Datenbank speichert Zeiten nur sekundengenau, gespeicherte Abstände
  /// sind also ganze Sekunden. Der gewöhnliche Median wäre dann immer eine
  /// ganze oder halbe Zahl (3,0 oder 4,0 s statt 3,4 s), und der Verlauf
  /// sähe wie eine Treppe aus. Bei ganzzahligen Werten wird deshalb in der
  /// mittleren Klasse (k − 0,5 bis k + 0,5) interpoliert, wie bei einem Median
  /// aus gerundeten Messwerten üblich.
  static double? median(List<double> values) {
    if (values.isEmpty) return null;
    final s = [...values]..sort();
    if (s.every((v) => v == v.roundToDouble())) {
      final half = s.length / 2;
      var below = 0;
      var i = 0;
      while (i < s.length) {
        var j = i;
        while (j < s.length && s[j] == s[i]) {
          j++;
        }
        final count = j - i;
        if (below + count >= half) return s[i] - 0.5 + (half - below) / count;
        below += count;
        i = j;
      }
    }
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  static double? _ifEnough(List<double> values) => values.length < minSamples ? null : median(values);
}

/// Eine Aufnahme mit ihren Zeiten.
class TempoVisit {
  const TempoVisit({
    required this.start,
    required this.darts,
    required this.gaps,
    this.cycle,
    this.points,
  });

  /// Zeit des ersten Darts.
  final DateTime start;
  final int darts;

  /// Wurfabstände in Sekunden; `null` = unsichere Zeiten, die Aufnahme zählt
  /// nicht.
  final List<double>? gaps;

  /// Erster Dart bis erster Dart der nächsten Aufnahme in Sekunden (nur
  /// Training, volle Aufnahme, Pause unter [TempoRules.maxPause]).
  final double? cycle;

  /// Punkte der vollen Aufnahme (drei gezählte Darts) in Spielen, in denen
  /// auf Punkte geworfen wird.
  final int? points;

  bool get timed => gaps != null;

  /// Erster bis letzter Dart in Sekunden (ab zwei Darts).
  double? get span => gaps == null || darts < 2 ? null : gaps!.fold<double>(0, (a, b) => a + b);

  /// Volle Aufnahme mit drei Darts und verlässlichen Zeiten.
  bool get full => timed && darts == 3;
}

/// Zeiten einer Session (einmal berechnet, zwischengespeichert).
class SessionTempo {
  const SessionTempo(this.group, this.visits);

  final TempoGroup group;
  final List<TempoVisit> visits;

  /// Mindestens eine Aufnahme mit verlässlichen Zeiten.
  bool get usable => visits.any((v) => v.timed);

  /// Eine Session mit Würfen, aber ohne verlässliche Zeiten.
  bool get hasThrows => visits.isNotEmpty;

  static SessionTempo of(SessionRow s, List<ThrowRow> throws) {
    final group = TempoGroup.of(s.gameId);
    final scoring = isVisitScoringGame(s.gameId);
    final groups = <List<ThrowRow>>[];
    int? current;
    for (final t in throws) {
      if (t.visitIndex != current) {
        groups.add([]);
        current = t.visitIndex;
      }
      groups.last.add(t);
    }
    bool timedRow(ThrowRow t) => TempoRules.isTimedRow(t, s.startedAt);
    final visits = <TempoVisit>[];
    for (final (i, v) in groups.indexed) {
      final gaps = TempoRules.gapsOf([for (final t in v) (time: t.timestamp, timed: timedRow(t))]);
      double? cycle;
      // Wer wirft zwischen zwei Aufnahmen? Nur im Training immer man selbst.
      if (gaps != null && group == TempoGroup.training && v.length == 3 && i + 1 < groups.length) {
        final next = groups[i + 1].first;
        final c = next.timestamp.difference(v.first.timestamp).inMilliseconds / 1000;
        if (timedRow(next) && c >= TempoRules.minGap && c <= TempoRules.maxPause) cycle = c;
      }
      int? points;
      if (scoring) {
        final counted = [for (final t in v) if (t.counted) t];
        if (counted.length == 3) points = counted.fold<int>(0, (a, t) => a + t.score);
      }
      visits.add(TempoVisit(start: v.first.timestamp, darts: v.length, gaps: gaps, cycle: cycle, points: points));
    }
    return SessionTempo(group, visits);
  }
}

/// Kennzahlen einer Gruppe von Aufnahmen. Eine Zahl ist `null` („zu wenig
/// Daten“), solange weniger als [TempoRules.minSamples] Messwerte dahinterstehen.
class TempoFigures {
  const TempoFigures({
    required this.visits,
    required this.gapCount,
    required this.fullVisits,
    required this.cycleCount,
    this.perDart,
    this.perVisit,
    this.withTakeout,
  });

  static const TempoFigures empty = TempoFigures(visits: 0, gapCount: 0, fullVisits: 0, cycleCount: 0);

  /// Aufnahmen mit verlässlichen Zeiten.
  final int visits;

  /// Messwerte hinter den Zahlen.
  final int gapCount;
  final int fullVisits;
  final int cycleCount;

  /// Median der Wurfabstände in Sekunden.
  final double? perDart;

  /// Median der Aufnahmezeit (erster bis dritter Dart) in Sekunden.
  final double? perVisit;

  /// Median der Zeit mit Takeout in Sekunden (nur Training).
  final double? withTakeout;

  bool get isEmpty => visits == 0;

  static TempoFigures of(Iterable<TempoVisit> all) {
    final gaps = <double>[];
    final spans = <double>[];
    final cycles = <double>[];
    var visits = 0;
    for (final v in all) {
      if (!v.timed) continue;
      visits++;
      gaps.addAll(v.gaps!);
      if (v.full) spans.add(v.span!);
      if (v.cycle != null) cycles.add(v.cycle!);
    }
    return TempoFigures(
      visits: visits,
      gapCount: gaps.length,
      fullVisits: spans.length,
      cycleCount: cycles.length,
      perDart: TempoRules._ifEnough(gaps),
      perVisit: TempoRules._ifEnough(spans),
      withTakeout: TempoRules._ifEnough(cycles),
    );
  }
}

/// Median der Wurfabstände einer Kalenderwoche.
class TempoWeek {
  const TempoWeek(this.weekStart, this.perDart, this.gapCount);
  final DateTime weekStart;
  final double perDart;
  final int gapCount;
}

/// Durchschnittspunkte der vollen Aufnahmen einer Tempoklasse.
class TempoBandStats {
  const TempoBandStats(this.band, this.visits, this.averagePoints);
  final TempoBand band;
  final int visits;

  /// `null` ab weniger als [TempoRules.minSamples] Aufnahmen.
  final double? averagePoints;
}

/// Auswertung des Wurftempos für Zeitraum und Spiel.
class TempoReport {
  const TempoReport({
    required this.all,
    required this.byGroup,
    required this.weeks,
    required this.bands,
    required this.sessions,
    required this.sessionsUsed,
  });

  /// Alle verwendeten Aufnahmen.
  final TempoFigures all;
  final Map<TempoGroup, TempoFigures> byGroup;

  /// Wochen mit genug Daten, älteste zuerst (letzte [TempoRules.trendWeeks]
  /// Wochen, unabhängig vom gewählten Zeitraum).
  final List<TempoWeek> weeks;

  /// Schnell, mittel, langsam – immer drei Einträge.
  final List<TempoBandStats> bands;

  /// Sessions mit Würfen im Zeitraum und davon die mit verlässlichen Zeiten.
  final int sessions;
  final int sessionsUsed;

  bool get isEmpty => sessions == 0;
  int get sessionsSkipped => sessions - sessionsUsed;

  TempoFigures group(TempoGroup g) => byGroup[g] ?? TempoFigures.empty;

  /// Unterschied der Durchschnittspunkte langsam minus schnell; `null`, wenn
  /// eine der beiden Klassen zu wenig Aufnahmen hat.
  double? get slowMinusFast {
    final fast = bands[TempoBand.fast.index].averagePoints;
    final slow = bands[TempoBand.slow.index].averagePoints;
    return fast == null || slow == null ? null : slow - fast;
  }

  static TempoReport build({
    required Iterable<SessionTempo> sessions,
    required Iterable<(DateTime weekStart, List<TempoVisit> visits)> trend,
  }) {
    final used = <SessionTempo>[];
    var withThrows = 0;
    for (final s in sessions) {
      if (!s.hasThrows) continue;
      withThrows++;
      if (s.usable) used.add(s);
    }
    final byGroup = <TempoGroup, TempoFigures>{
      for (final g in TempoGroup.values) g: TempoFigures.of([for (final s in used) if (s.group == g) ...s.visits]),
    };
    final points = <TempoBand, List<int>>{for (final b in TempoBand.values) b: []};
    for (final s in used) {
      for (final v in s.visits) {
        if (v.full && v.points != null) points[TempoBand.of(v.span!)]!.add(v.points!);
      }
    }
    final weeks = <TempoWeek>[];
    for (final (start, visits) in trend) {
      final gaps = [for (final v in visits) if (v.timed) ...v.gaps!];
      final m = TempoRules._ifEnough(gaps);
      if (m != null) weeks.add(TempoWeek(start, m, gaps.length));
    }
    return TempoReport(
      all: TempoFigures.of([for (final s in used) ...s.visits]),
      byGroup: byGroup,
      weeks: weeks,
      bands: [
        for (final b in TempoBand.values)
          TempoBandStats(
            b,
            points[b]!.length,
            points[b]!.length < TempoRules.minSamples ? null : points[b]!.fold<int>(0, (a, p) => a + p) / points[b]!.length,
          ),
      ],
      sessions: withThrows,
      sessionsUsed: used.length,
    );
  }
}

/// Tempo der laufenden Aufnahme für die Spielansicht.
///
/// Ohne Uhr: Alles kommt aus den Zeiten der Darts, die Anzeige ändert sich
/// nur, wenn ein Dart dazukommt oder die Aufnahme endet.
class LiveTempo {
  const LiveTempo({this.visit, this.perDart});

  /// Erster bis letzter Dart der jüngsten Aufnahme mit mindestens zwei Darts
  /// (Sekunden).
  final double? visit;

  /// Median der Wurfabstände der gezeigten Aufnahmen; erst ab
  /// [TempoRules.minSamples] Abständen.
  final double? perDart;

  bool get isEmpty => visit == null && perDart == null;

  /// [visits]: Aufnahmen der Session, älteste zuerst, die letzte darf noch
  /// laufen. `null`, wenn es nichts zu zeigen gibt: keine verlässlichen Zeiten
  /// (Simulator, manuelle Eingabe, von Hand korrigierte Darts) oder noch zu
  /// wenig Darts.
  static LiveTempo? ofVisits(List<List<DartThrow>> visits) => of([
        for (final v in visits)
          if (v.isNotEmpty) [for (final d in v) (time: d.timestamp, timed: d.source.name == TempoRules.timedSource)],
      ]);

  /// Wie [ofVisits], aus Darts mit der Nummer ihrer Aufnahme (Aufzeichnungen
  /// eines Spiels). Es zählen die letzten [lastVisits] Aufnahmen.
  static LiveTempo? ofDarts(Iterable<({int visit, DartThrow dart})> darts, {int lastVisits = 9}) {
    final visits = <List<DartThrow>>[];
    int? current;
    for (final d in darts) {
      if (d.visit != current) {
        visits.add([]);
        current = d.visit;
      }
      visits.last.add(d.dart);
    }
    return ofVisits(visits.length > lastVisits ? visits.sublist(visits.length - lastVisits) : visits);
  }

  static LiveTempo? of(List<List<TimedDart>> visits) {
    double? visit;
    for (final v in visits.reversed) {
      if (v.length < 2) continue;
      final gaps = TempoRules.gapsOf(v);
      if (gaps != null) visit = gaps.fold<double>(0, (a, b) => a + b);
      break;
    }
    final all = <double>[];
    for (final v in visits) {
      final gaps = TempoRules.gapsOf(v);
      if (gaps != null) all.addAll(gaps);
    }
    final perDart = TempoRules._ifEnough(all);
    final tempo = LiveTempo(visit: visit, perDart: perDart);
    return tempo.isEmpty ? null : tempo;
  }
}

/// Sekunden für die Anzeige: unter zehn mit einer Stelle („3,4 s“), sonst
/// ganz („17 s“).
String formatSeconds(double seconds) {
  if (seconds < 9.95) return '${seconds.toStringAsFixed(1).replaceAll('.', ',')} s';
  return '${math.max(0, seconds.round())} s';
}
