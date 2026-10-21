import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 14, 20); // Mittwoch
var _id = 0;

SessionRow session(String gameId, DateTime start) => SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: gameId,
      configJson: '{}',
      seed: 1,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 20)),
      finished: true,
      resultJson: jsonEncode({'metrics': {}, 'details': {}}),
      dartCount: 0,
    );

ThrowRow dart(SessionRow s, int seq, int visit, DateTime at, {String segment = 'T20', String source = 'autodartsLocal', bool counted = true}) {
  final seg = Segment.tryParse(segment)!;
  return ThrowRow(
    id: ++_id,
    sessionId: s.id,
    playerId: 1,
    gameId: s.gameId,
    seq: seq,
    visitIndex: visit,
    counted: counted,
    segment: seg.name,
    number: seg.number,
    multiplier: seg.multiplier,
    bed: seg.bed.name,
    score: seg.score,
    x: null,
    y: null,
    source: source,
    timestamp: at,
    rawJson: null,
  );
}

/// Aufnahmen mit je drei Darts im Abstand [gap] Sekunden; zwischen zwei
/// Aufnahmen vergehen [between] Sekunden (erster Dart bis erster Dart).
List<ThrowRow> visits(
  SessionRow s,
  int count, {
  double gap = 3,
  double between = 15,
  String source = 'autodartsLocal',
  String segment = 'T20',
  int firstVisit = 0,
  DateTime? from,
}) {
  final start = from ?? s.startedAt;
  final out = <ThrowRow>[];
  for (var v = 0; v < count; v++) {
    for (var d = 0; d < 3; d++) {
      final at = start.add(Duration(milliseconds: (v * between * 1000 + d * gap * 1000).round()));
      out.add(dart(s, (firstVisit + v) * 3 + d, firstVisit + v, at, source: source, segment: segment));
    }
  }
  return out;
}

StatsCalculator calc(List<SessionRow> sessions, List<ThrowRow> throws) =>
    StatsCalculator(sessions: sessions, throws: throws, now: now);

void main() {
  group('Wurfabstand und Aufnahmezeit', () {
    test('Median der Abstände, Aufnahmezeit und Zeit mit Takeout im Training', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final c = calc([s], visits(s, 12, gap: 3, between: 15));
      final r = c.tempoReport(StatsPeriod.month);
      expect(r.sessions, 1);
      expect(r.sessionsUsed, 1);
      expect(r.all.visits, 12);
      expect(r.all.gapCount, 24);
      expect(r.all.perDart, 3.0);
      expect(r.all.perVisit, 6.0);
      // Elf Übergänge (die letzte Aufnahme hat keine nächste).
      expect(r.all.cycleCount, 11);
      expect(r.all.withTakeout, 15.0);
      // Zehn Aufnahmen: nur neun Übergänge, die Zeit mit Takeout fehlt noch.
      final fewer = calc([s], visits(s, 10, gap: 3, between: 15)).tempoReport(StatsPeriod.month);
      expect(fewer.all.perVisit, 6.0);
      expect(fewer.all.withTakeout, isNull);
    });

    test('Median statt Mittelwert: ein Ausreißer ändert nichts', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 10, gap: 3, between: 15);
      // Ein Abstand von 50 s (Dart gesucht) in der letzten Aufnahme.
      final last = rows.last;
      rows[rows.length - 1] = dart(s, last.seq, last.visitIndex, last.timestamp.add(const Duration(seconds: 47)));
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.all.gapCount, 20);
      expect(r.all.perDart, closeTo(3.0, 0.05));
    });

    test('Pause zwischen Aufnahmen: über 60 s zählt nicht zur Zeit mit Takeout', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = <ThrowRow>[
        ...visits(s, 6, gap: 3, between: 15),
        // 5 Minuten Pause, danach sieben weitere Aufnahmen.
        ...visits(s, 7, gap: 3, between: 15, firstVisit: 6, from: s.startedAt.add(const Duration(minutes: 6))),
      ];
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      // 13 Aufnahmen, 12 Übergänge, davon der über die Pause nicht.
      expect(r.all.visits, 13);
      expect(r.all.cycleCount, 11);
      expect(r.all.withTakeout, 15.0);
    });

    test('Ein Abstand über 60 s in der Aufnahme lässt die ganze Aufnahme weg', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12, gap: 3, between: 15);
      // Zweiter Dart der ersten Aufnahme 90 s nach dem ersten.
      rows[1] = dart(s, 1, 0, s.startedAt.add(const Duration(seconds: 90)));
      rows[2] = dart(s, 2, 0, s.startedAt.add(const Duration(seconds: 93)));
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.all.visits, 11);
      expect(r.all.gapCount, 22);
    });

    test('Gleiche Zeit für mehrere Darts (von Hand ergänzt) ist kein Tempo', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12, gap: 0, between: 15);
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.sessions, 1);
      expect(r.sessionsUsed, 0);
      expect(r.sessionsSkipped, 1);
      expect(r.all.isEmpty, isTrue);
      expect(r.all.perDart, isNull);
    });

    test('Zeiten rückwärts (Reihenfolge verdreht) lassen die Aufnahme weg', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12, gap: 3, between: 15);
      rows[4] = dart(s, 4, 1, rows[3].timestamp.subtract(const Duration(seconds: 2)));
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.all.visits, 11);
    });
  });

  group('Welche Würfe zählen', () {
    test('Simulator und manuelle Eingabe haben keine verlässliche Zeit', () {
      final sim = session('highscore_hunt', now.subtract(const Duration(hours: 3)));
      final man = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final board = session('highscore_hunt', now.subtract(const Duration(hours: 1)));
      final r = calc([sim, man, board], [
        ...visits(sim, 12, source: 'simulator'),
        ...visits(man, 12, source: 'manual'),
        ...visits(board, 12),
      ]).tempoReport(StatsPeriod.month);
      expect(r.sessions, 3);
      expect(r.sessionsUsed, 1);
      expect(r.sessionsSkipped, 2);
      expect(r.all.visits, 12);
    });

    test('Von Hand korrigierter Dart: nur diese Aufnahme fällt heraus', () {
      final s = session('autodarts_live', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12, gap: 3, between: 15);
      // Korrektur von Hand: gleiche Zeit, Quelle manual.
      rows[7] = dart(s, 7, 2, rows[7].timestamp, source: 'manual', segment: 'S20');
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.sessionsUsed, 1);
      expect(r.all.visits, 11);
    });

    test('Nachträglich geschriebene Würfe (vor Beginn der Session) zählen nicht', () {
      final s = session('x01_match', now.subtract(const Duration(hours: 1)));
      // Fortgesetztes Match: acht Aufnahmen stammen von früher, vier sind neu.
      final old = visits(s, 8, from: s.startedAt.subtract(const Duration(days: 1)));
      final fresh = visits(s, 4, firstVisit: 8, from: s.startedAt.add(const Duration(minutes: 1)));
      final r = calc([s], [...old, ...fresh]).tempoReport(StatsPeriod.month);
      expect(r.all.visits, 4);
      expect(r.all.perDart, isNull); // 8 Abstände: zu wenig
      expect(r.all.gapCount, 8);
    });

    test('Match und Online: nur Wurfabstände und Aufnahmezeit, keine Zeit mit Takeout', () {
      final m = session('x01_match', now.subtract(const Duration(hours: 3)));
      final l = session('x01_live', now.subtract(const Duration(hours: 2)));
      final t = session('highscore_hunt', now.subtract(const Duration(hours: 1)));
      final r = calc([m, l, t], [
        ...visits(m, 12, gap: 4, between: 25),
        ...visits(l, 12, gap: 2, between: 30),
        ...visits(t, 12, gap: 3, between: 12),
      ]).tempoReport(StatsPeriod.month);
      expect(r.group(TempoGroup.match).perDart, 4.0);
      expect(r.group(TempoGroup.match).withTakeout, isNull);
      expect(r.group(TempoGroup.match).cycleCount, 0);
      expect(r.group(TempoGroup.live).perDart, 2.0);
      expect(r.group(TempoGroup.live).perVisit, 4.0);
      expect(r.group(TempoGroup.training).perDart, 3.0);
      expect(r.group(TempoGroup.training).withTakeout, 12.0);
      expect(r.all.visits, 36);
      expect(r.all.perDart, 3.0);
    });
  });

  group('Rückgängig, Neustart, wenig Daten', () {
    test('Rückgängig: der gelöschte Dart steht nicht in der Datenbank, die übrigen zählen', () {
      final s = session('autodarts_live', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12, gap: 3, between: 15);
      // Dart 3 der letzten Aufnahme zurückgenommen: die Aufnahme hat zwei Darts.
      rows.removeLast();
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.all.visits, 12);
      expect(r.all.fullVisits, 11);
      expect(r.all.gapCount, 23);
    });

    test('Session beendet und neu begonnen: kein Abstand über die Sessions hinweg', () {
      final a = session('highscore_hunt', now.subtract(const Duration(hours: 3)));
      final b = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final r = calc([a, b], [...visits(a, 6, between: 15), ...visits(b, 6, between: 15)]).tempoReport(StatsPeriod.month);
      expect(r.all.visits, 12);
      // Je Session fünf Übergänge, keiner zwischen den Sessions.
      expect(r.all.cycleCount, 10);
      expect(r.all.withTakeout, 15.0);
    });

    test('Zu wenig Daten: Zahl bleibt leer, auch bei einer ganzen Aufnahme', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final r = calc([s], visits(s, 4)).tempoReport(StatsPeriod.month);
      expect(r.isEmpty, isFalse);
      expect(r.all.visits, 4);
      expect(r.all.gapCount, 8);
      expect(r.all.perDart, isNull);
      expect(r.all.perVisit, isNull);
      expect(r.weeks, isEmpty);
    });

    test('Ohne Würfe: leer', () {
      final r = calc([], []).tempoReport(StatsPeriod.month);
      expect(r.isEmpty, isTrue);
      expect(r.all.perDart, isNull);
      expect(r.bands.length, 3);
    });

    test('Ein Tag mit wenigen Aufnahmen bekommt keinen Punkt im Verlauf', () {
      final dayA = now.subtract(const Duration(days: 14)); // mehrere Aufnahmen
      final dayB = now.subtract(const Duration(days: 7)); // nur drei
      final dayC = now.subtract(const Duration(days: 1));
      final a = session('highscore_hunt', dayA);
      final b = session('highscore_hunt', dayB);
      final c = session('highscore_hunt', dayC);
      final r = calc([a, b, c], [
        ...visits(a, 8, gap: 4),
        ...visits(b, 3, gap: 2),
        ...visits(c, 8, gap: 3),
      ]).tempoReport(StatsPeriod.all);
      expect(r.weeks.length, 2);
      expect(r.weeks.first.perDart, 4.0);
      expect(r.weeks.last.perDart, 3.0);
      expect(r.weeks.first.weekStart.isBefore(r.weeks.last.weekStart), isTrue);
    });

    test('Verlauf deckt zwölf Wochen ab, ältere Sessions nicht', () {
      final old = session('highscore_hunt', now.subtract(const Duration(days: 7 * 20)));
      final recent = session('highscore_hunt', now.subtract(const Duration(days: 3)));
      final r = calc([old, recent], [...visits(old, 8), ...visits(recent, 8)]).tempoReport(StatsPeriod.all);
      expect(r.weeks.length, 1);
      // Die Kennzahlen des Zeitraums „Alles“ enthalten beide.
      expect(r.all.visits, 16);
    });
  });

  group('Tempo und Punkte', () {
    test('Tempoklassen nach der Aufnahmezeit, Durchschnittspunkte je Klasse', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = <ThrowRow>[
        // Schnell: 2 s Abstand = 4 s, nur Single 20.
        ...visits(s, 10, gap: 2, between: 20, segment: 'S20'),
        // Mittel: 4 s = 8 s, Triple 20.
        ...visits(s, 10, gap: 4, between: 20, segment: 'T20', firstVisit: 10, from: s.startedAt.add(const Duration(minutes: 10))),
        // Langsam: 8 s = 16 s, Triple 20.
        ...visits(s, 10, gap: 8, between: 30, segment: 'T20', firstVisit: 20, from: s.startedAt.add(const Duration(minutes: 20))),
      ];
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.bands.map((b) => b.visits), [10, 10, 10]);
      expect(r.bands[0].averagePoints, 60);
      expect(r.bands[1].averagePoints, 180);
      expect(r.bands[2].averagePoints, 180);
      expect(r.slowMinusFast, 120);
    });

    test('Zu wenige Aufnahmen in einer Klasse: keine Zahl', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = [
        ...visits(s, 12, gap: 3, segment: 'T20'),
        ...visits(s, 3, gap: 8, between: 30, firstVisit: 12, from: s.startedAt.add(const Duration(minutes: 20))),
      ];
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.bands[TempoBand.medium.index].averagePoints, 180);
      expect(r.bands[TempoBand.slow.index].visits, 3);
      expect(r.bands[TempoBand.slow.index].averagePoints, isNull);
      expect(r.slowMinusFast, isNull);
    });

    test('Spiele ohne Punktewertung bleiben aus den Klassen', () {
      final s = session('around_the_clock', now.subtract(const Duration(hours: 2)));
      final r = calc([s], visits(s, 12)).tempoReport(StatsPeriod.month);
      expect(r.all.perVisit, 6.0);
      expect(r.bands.every((b) => b.visits == 0), isTrue);
    });

    test('Nicht gezählte Darts (nach Bust) zählen zeitlich, aber nicht für die Punkte', () {
      final s = session('x01', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12, gap: 3, segment: 'T20');
      // Erste Aufnahme: letzter Dart nicht gezählt.
      rows[2] = dart(s, 2, 0, rows[2].timestamp, counted: false);
      final r = calc([s], rows).tempoReport(StatsPeriod.month);
      expect(r.all.fullVisits, 12);
      expect(r.bands[TempoBand.fast.index].visits + r.bands[TempoBand.medium.index].visits, 11);
    });
  });

  group('Zwischenspeicher', () {
    test('Unveränderte Sessions behalten ihre Zeiten, der Bericht ist je Zeitraum gemerkt', () {
      final s = session('highscore_hunt', now.subtract(const Duration(hours: 2)));
      final rows = visits(s, 12);
      final first = calc([s], rows);
      final a = first.tempoReport(StatsPeriod.month);
      expect(identical(a, first.tempoReport(StatsPeriod.month)), isTrue);
      expect(identical(a, first.tempoReport(StatsPeriod.week)), isFalse);
      expect(identical(first.tempoOf(s), first.tempoOf(s)), isTrue);

      final second = StatsCalculator(sessions: [s], throws: rows, now: now, previous: first, unchanged: {s.id});
      expect(identical(second.tempoOf(s), first.tempoOf(s)), isTrue);
      expect(second.tempoReport(StatsPeriod.month).all.perDart, 3.0);
    });

    test('Spielfilter wirkt auf Kennzahlen und Verlauf', () {
      final a = session('highscore_hunt', now.subtract(const Duration(days: 2)));
      final b = session('x01_live', now.subtract(const Duration(days: 1)));
      final c = calc([a, b], [...visits(a, 8, gap: 3), ...visits(b, 8, gap: 5)]);
      expect(c.tempoReport(StatsPeriod.month, gameId: 'x01_live').all.perDart, 5.0);
      expect(c.tempoReport(StatsPeriod.month, gameId: 'highscore_hunt').all.perDart, 3.0);
      expect(c.tempoReport(StatsPeriod.month).all.gapCount, 32);
      expect(c.tempoReport(StatsPeriod.month, gameId: 'x01_live').weeks.single.perDart, 5.0);
    });
  });

  group('LiveTempo', () {
    List<TimedDart> v(List<double> secs, {bool timed = true}) => [
          for (final s in secs) (time: now.add(Duration(milliseconds: (s * 1000).round())), timed: timed),
        ];

    test('Aufnahmezeit der jüngsten Aufnahme, Ø je Dart erst mit genug Abständen', () {
      final one = LiveTempo.of([v([0, 3, 7])])!;
      expect(one.visit, 7.0);
      expect(one.perDart, isNull);
      final many = LiveTempo.of([for (var i = 0; i < 6; i++) v([i * 20.0, i * 20 + 3, i * 20 + 6])])!;
      expect(many.visit, 6.0);
      expect(many.perDart, 3.0);
    });

    test('Laufende Aufnahme mit einem Dart: zeigt die vorige Aufnahme', () {
      final t = LiveTempo.of([v([0, 3, 7]), v([30])])!;
      expect(t.visit, 7.0);
    });

    test('Unsichere Zeiten (Simulator, manuell): nichts anzeigen', () {
      expect(LiveTempo.of([v([0, 3, 7], timed: false)]), isNull);
      expect(LiveTempo.of([v([0])]), isNull);
      expect(LiveTempo.of([]), isNull);
      // Gleiche Zeit (von Hand ergänzt).
      expect(LiveTempo.of([v([0, 0, 0])]), isNull);
    });

    test('Die jüngste Aufnahme ist unsicher: keine Zeit der vorigen als aktuelle ausgeben', () {
      final t = LiveTempo.of([v([0, 3, 7]), v([30, 30, 30])]);
      expect(t, isNull);
    });
  });

  test('Sekunden-Format', () {
    expect(formatSeconds(3.04), '3,0 s');
    expect(formatSeconds(3.46), '3,5 s');
    expect(formatSeconds(9.96), '10 s');
    expect(formatSeconds(17.4), '17 s');
  });

  test('Median: bei ganzen Sekunden (Datenbank) in der mittleren Klasse interpoliert', () {
    expect(TempoRules.median([]), isNull);
    expect(TempoRules.median([3, 3, 3, 4, 4, 4, 4, 4]), closeTo(3.7, 1e-9));
    expect(TempoRules.median([3, 3, 3, 3, 3, 3, 3, 3, 3, 3]), 3.0);
    expect(TempoRules.median([2, 3, 4]), 3.0);
    // Mit Bruchteilen (Zeiten im Speicher): gewöhnlicher Median.
    expect(TempoRules.median([1.2, 3.1, 3.4, 9.9]), closeTo(3.25, 1e-9));
    expect(TempoRules.median([4.5]), 4.5);
  });

  test('Gruppen', () {
    expect(TempoGroup.of('x01_match'), TempoGroup.match);
    expect(TempoGroup.of('x01_live'), TempoGroup.live);
    expect(TempoGroup.of('autodarts_live'), TempoGroup.live);
    expect(TempoGroup.of('x01'), TempoGroup.training);
    expect(DartSourceKind.autodartsLocal.name, TempoRules.timedSource);
  });
}
