import 'dart:convert';
import 'dart:math' as math;

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

const double _mm = BoardGeometry.boardRadiusMm;
final now = DateTime(2026, 10, 11, 18);
var _id = 0;

/// Punkt mit Abweichung ([t] rechts, [r] oben, in mm) vom Mittelpunkt von
/// [field], in den Achsen des Felds.
BoardPoint near(Segment field, {double t = 0, double r = 0}) {
  final c = BoardGeometry.centerOf(field);
  final f = FieldFrame.of(field);
  return BoardPoint(
    c.x + (t * f.tangential.x + r * f.radial.x) / _mm,
    c.y + (t * f.tangential.y + r * f.radial.y) / _mm,
  );
}

SessionRow session(String gameId, {Map<String, Object?> config = const {}, int seed = 1, DateTime? start}) {
  final s = start ?? now.subtract(const Duration(days: 1));
  return SessionRow(
    id: ++_id,
    uid: 's$_id',
    playerId: 1,
    gameId: gameId,
    configJson: jsonEncode(config),
    seed: seed,
    startedAt: s,
    endedAt: s.add(const Duration(minutes: 10)),
    finished: true,
    resultJson: jsonEncode({'metrics': {}, 'details': {}}),
    dartCount: 0,
  );
}

/// Gespeicherter Wurf; mit [p] liegt das Feld an der Position.
ThrowRow row({
  BoardPoint? p,
  String? segment,
  String source = 'simulator',
  int sessionId = 0,
  String gameId = 'x',
  int seq = 0,
  int visit = 0,
  bool counted = true,
}) {
  final seg = segment != null ? Segment.tryParse(segment)! : (p == null ? Segment.miss : BoardGeometry.segmentAt(p));
  return ThrowRow(
    id: ++_id,
    sessionId: sessionId,
    playerId: 1,
    gameId: gameId,
    seq: seq,
    visitIndex: visit,
    counted: counted,
    segment: seg.name,
    number: seg.number,
    multiplier: seg.multiplier,
    bed: seg.bed.name,
    score: seg.score,
    x: p?.x,
    y: p?.y,
    source: source,
    timestamp: now,
    rawJson: null,
  );
}

/// [n] Darts als Kreuz um eine mittlere Abweichung ([t], [r]) mit den
/// Ausschlägen [a] (seitlich) und [b] (Höhe), alle mm.
List<ScatterDart> cross(Segment field, int n, {double t = 0, double r = 0, double a = 15, double b = 15, bool exact = true}) => [
      for (var i = 0; i < n; i++)
        ScatterDart(
          field: field,
          position: near(field, t: t + [a, -a, 0, 0][i % 4], r: r + [0, 0, b, -b][i % 4]),
          hit: i % 5 == 0,
          exact: exact,
        ),
    ];

final t20 = Segment.triple(20);
final t19 = Segment.triple(19);
final t3 = Segment.triple(3);
final d11 = Segment.double(11);
final d16 = Segment.double(16);

void main() {
  group('Achsen des Felds', () {
    test('T20 oben: links/rechts und hoch/tief wie an der Scheibe', () {
      final f = FieldFrame.of(t20);
      final o = f.decompose(const BoardPoint(-0.02, -0.03));
      expect(o.t, closeTo(-0.02, 1e-9));
      expect(o.r, closeTo(-0.03, 1e-9));
      expect(f.upper, isTrue);
      expect(f.tangentialIsHorizontal, isTrue);
    });

    test('T3 unten: an der Scheibe rechts ist im Feld links, nach unten ist außen', () {
      final f = FieldFrame.of(t3);
      final right = f.decompose(const BoardPoint(0.02, 0));
      expect(right.t, closeTo(-0.02, 1e-9));
      expect(right.r, closeTo(0, 1e-9));
      final down = f.decompose(const BoardPoint(0, -0.02));
      expect(down.r, closeTo(0.02, 1e-9));
      expect(f.upper, isFalse);
      expect(f.tangentialIsHorizontal, isTrue);
    });

    test('D11 links: nach links ist außen, nach oben ist rechts (Richtung 14)', () {
      final f = FieldFrame.of(d11);
      final left = f.decompose(const BoardPoint(-0.02, 0));
      expect(left.r, closeTo(0.02, 1e-9));
      expect(left.t, closeTo(0, 1e-9));
      final up = f.decompose(const BoardPoint(0, 0.02));
      expect(up.t, closeTo(0.02, 1e-9));
      expect(neighbourOf(d11, right: true), 14);
      expect(neighbourOf(d11, right: false), 8);
      expect(f.tangentialIsHorizontal, isFalse);
    });

    test('T6 rechts: nach unten ist rechts (Richtung 10)', () {
      final f = FieldFrame.of(Segment.triple(6));
      expect(f.decompose(const BoardPoint(0, -0.02)).t, closeTo(0.02, 1e-9));
      expect(neighbourOf(Segment.triple(6), right: true), 10);
    });

    test('Oben gelten 5, 20, 1, 12 und 18, nicht 4 oder 9', () {
      for (final n in [20, 1, 18, 5, 12]) {
        expect(FieldFrame.of(Segment.triple(n)).upper, isTrue, reason: '$n');
      }
      for (final n in [4, 9, 3, 11]) {
        expect(FieldFrame.of(Segment.triple(n)).upper, isFalse, reason: '$n');
      }
    });

    test('Bull: Achsen der Scheibe, ohne Nachbarzahl', () {
      final f = FieldFrame.of(Segment.bull);
      expect(f.decompose(const BoardPoint(0.01, -0.02)), (t: 0.01, r: -0.02));
      expect(f.upper, isTrue);
      expect(neighbourOf(Segment.bull, right: true), isNull);
    });

    test('Richtung in acht Sektoren, kleine Abweichung mittig', () {
      expect(ScatterDirection.of(-3, -4, 2), ScatterDirection.downLeft);
      expect(ScatterDirection.of(0.5, 0.5, 2), ScatterDirection.center);
      expect(ScatterDirection.of(5, 0.5, 1), ScatterDirection.right);
      expect(ScatterDirection.of(0, -5, 1), ScatterDirection.down);
      expect(ScatterDirection.of(3, 3, 1), ScatterDirection.upRight);
      expect(ScatterDirection.of(-3, 3, 1), ScatterDirection.upLeft);
      expect(ScatterDirection.of(-5, 1, 1), ScatterDirection.left);
    });
  });

  group('Ziel je Dart', () {
    test('Genau ein Double, Triple oder Bull ist ein exaktes Ziel, Singles nicht', () {
      expect(aimFieldOf({t20}), t20);
      expect(aimFieldOf({d16}), d16);
      expect(aimFieldOf({Segment.bull, Segment.outerBull}), Segment.bull);
      expect(aimFieldOf({Segment.outerBull}), Segment.bull);
      expect(aimFieldOf({Segment.single(20)}), isNull);
      expect(aimFieldOf({Segment.single(20), Segment.single(20, inner: true)}), isNull);
      expect(aimFieldOf({t20, Segment.double(20)}), isNull);
      expect(aimFieldOf(const {}), isNull);
    });

    test('Schätzung: T20 aus 20/1/5, T19 aus 19/7/3, Bull nah an der Mitte', () {
      Segment? infer(BoardPoint p, {bool t20 = true, bool t19 = true, bool bull = true}) =>
          inferCluster(p, t20: t20, t19: t19, bull: bull);
      for (final n in [20, 1, 5]) {
        expect(infer(BoardGeometry.centerOf(Segment.triple(n))), t20, reason: '$n');
        expect(infer(BoardGeometry.centerOf(Segment.single(n))), t20, reason: 'S$n');
      }
      for (final n in [19, 7, 3]) {
        expect(infer(BoardGeometry.centerOf(Segment.triple(n))), t19, reason: '$n');
      }
      expect(infer(BoardGeometry.centerOf(Segment.triple(12))), isNull);
      expect(infer(BoardGeometry.polar(20 / _mm, 100)), Segment.bull);
      expect(infer(BoardGeometry.polar(20 / _mm, 100), bull: false), isNull);
      // Zwischen Bull und Triple: unklar.
      expect(infer(BoardGeometry.polar(40 / _mm, 0)), isNull);
      // Weit über dem Double-Ring.
      expect(infer(BoardGeometry.polar(200 / _mm, 0)), isNull);
      expect(infer(BoardGeometry.centerOf(t20), t20: false), isNull);
    });

    test('Exaktes Ziel aus dem Spiel; Treffer nach dem Feld', () {
      final p = near(t20, t: -3, r: -2);
      final d = scatterDartOf(row(p: p), BoardGeometry.segmentAt(p), TargetsAim({t20}))!;
      expect(d.field, t20);
      expect(d.exact, isTrue);
      expect(d.hit, isTrue);
      final low = near(t20, r: -12);
      expect(scatterDartOf(row(p: low), BoardGeometry.segmentAt(low), TargetsAim({t20}))!.hit, isFalse);
    });

    test('Manuell, ohne Position, Single-Ziel oder Ausreißer zählen nicht', () {
      final p = BoardGeometry.centerOf(t20);
      expect(scatterDartOf(row(p: p, source: 'manual'), t20, TargetsAim({t20})), isNull);
      expect(scatterDartOf(row(segment: 'T20'), t20, TargetsAim({t20})), isNull);
      expect(scatterDartOf(row(p: p), t20, TargetsAim({Segment.single(20)})), isNull);
      final far = BoardGeometry.centerOf(t3);
      expect(scatterDartOf(row(p: far), t3, TargetsAim({t20})), isNull);
    });

    test('Mehrere Ziele: nur erlaubte Scoring-Felder werden geschätzt', () {
      Set<Segment> cricket(int n) => {Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)};
      final p = BoardGeometry.centerOf(t20);
      final d = scatterDartOf(row(p: p), t20, TargetsAim(cricket(20)))!;
      expect(d.field, t20);
      expect(d.exact, isFalse);
      expect(scatterDartOf(row(p: p), t20, TargetsAim(cricket(19))), isNull);
      // Ohne Ziel (z. B. X01 über 170): schätzen.
      final q = BoardGeometry.centerOf(Segment.single(7));
      expect(scatterDartOf(row(p: q), Segment.single(7), const TargetsAim({}))!.field, t19);
    });

    test('Regel-Ziel, Scoring-Dart und unbekanntes Ziel', () {
      final p = near(d16, t: 4);
      expect(scatterDartOf(row(p: p), Segment.single(16), RuleAim(d16))!.exact, isFalse);
      const center = BoardPoint(0.01, 0.01);
      expect(scatterDartOf(row(p: center), Segment.bull, const ScoringAim()), isNull);
      final bull = scatterDartOf(row(p: center), Segment.outerBull, const UnknownAim())!;
      expect(bull.field, Segment.bull);
      expect(bull.hit, isTrue, reason: '25 zählt beim Bull als Treffer');
    });
  });

  group('X01 ohne angezeigtes Ziel', () {
    List<ThrowRow> darts(List<(String, int)> list) => [
          for (final (i, (s, v)) in list.indexed) row(segment: s, visit: v, seq: i),
        ];

    test('Scoring ab Rest 100, Finish-Doppel als Regel-Ziel, neues Leg nach Checkout', () {
      final aims = x01AimsOf(
        darts([('T20', 0), ('S9', 0), ('S16', 0), ('D8', 1), ('T20', 2)]),
        startScore: 101,
        out: OutMode.double,
      );
      expect(aims[0], isA<ScoringAim>());
      expect(aims[1], isNull, reason: 'Rest 41: Weg aus zwei Feldern');
      expect((aims[2]! as RuleAim).field, d16);
      expect((aims[3]! as RuleAim).field, Segment.double(8));
      expect(aims[4], isA<ScoringAim>(), reason: 'nach dem Checkout wieder 101');
    });

    test('Bust setzt den Rest zurück', () {
      final aims = x01AimsOf(darts([('S20', 0), ('T20', 0), ('D20', 1)]), startScore: 40, out: OutMode.double);
      expect((aims[0]! as RuleAim).field, Segment.double(20));
      expect((aims[1]! as RuleAim).field, Segment.double(10));
      expect((aims[2]! as RuleAim).field, Segment.double(20), reason: 'Bust: wieder Rest 40');
    });

    test('Verlorene Legs aus den Leg-Enden', () {
      final list = darts([('S20', 0), ('S1', 4)]);
      expect((x01AimsOf(list, startScore: 60, out: OutMode.double)[1]! as RuleAim).field, Segment.double(20));
      expect(x01AimsOf(list, startScore: 60, out: OutMode.double, legEnds: [1])[1], isNull, reason: 'neues Leg: Rest 60');
    });

    test('Double-In: vor dem Öffnen kein Ziel', () {
      final aims = x01AimsOf(darts([('S20', 0), ('D20', 0), ('T20', 0)]), startScore: 201, out: OutMode.double, doubleIn: true);
      expect(aims, [null, null, isA<ScoringAim>()]);
    });
  });

  group('Auswertung je Feld', () {
    for (final (field, t, r) in [(t20, -4.0, -5.0), (t3, -4.0, -5.0), (d11, 5.0, -2.0)]) {
      test('Abweichung im Feld: $field ($t, $r)', () {
        final f = FieldScatter.of(field, cross(field, 40, t: t, r: r, a: 18, b: 10));
        expect(f.offset.t, closeTo(t, 1e-6));
        expect(f.offset.r, closeTo(r, 1e-6));
        expect(f.sdT, greaterThan(f.sdR));
        expect(f.sdT, closeTo(18 * math.sqrt(20 / 39), 1e-6));
        expect(f.direction, ScatterDirection.of(t, r, f.shape.threshold));
        expect((f.hits.attempts, f.hits.hits), (40, 8));
      });
    }

    test('An der Scheibe: links unten bei T20, rechts oben bei T3', () {
      final a = FieldScatter.of(t20, cross(t20, 40, t: -4, r: -5));
      expect(a.mean.x, lessThan(a.center.x));
      expect(a.mean.y, lessThan(a.center.y));
      expect(a.direction, ScatterDirection.downLeft);
      final b = FieldScatter.of(t3, cross(t3, 40, t: -4, r: -5));
      expect(b.mean.x, greaterThan(b.center.x));
      expect(b.mean.y, greaterThan(b.center.y));
      expect(b.direction, ScatterDirection.downLeft);
    });

    test('Ellipse: große Achse in Richtung der stärkeren Streuung', () {
      final e = FieldScatter.of(t20, cross(t20, 40, a: 18, b: 10)).ellipse;
      expect(e.major * _mm, closeTo(18 * math.sqrt(20 / 39), 1e-6));
      expect(e.minor * _mm, closeTo(10 * math.sqrt(20 / 39), 1e-6));
      expect(e.angle.abs(), lessThan(1e-6));
      final side = FieldScatter.of(d11, cross(d11, 40, a: 18, b: 10)).ellipse;
      expect((side.angle.abs() - math.pi / 2).abs(), lessThan(1e-6), reason: 'D11: seitlich im Feld ist senkrecht');
    });
  });

  group('Mindestmenge', () {
    test('Ein Feld erscheint erst ab 30 Darts', () {
      expect(ScatterRules.minDarts, 30);
      final few = ScatterReport.build(cross(t20, 29));
      expect(few.isEmpty, isTrue);
      expect(few.overall, isNull);
      expect(few.pending.single, (field: t20, darts: 29));
      final enough = ScatterReport.build(cross(t20, 30));
      expect(enough.fields.single.field, t20);
      expect(enough.pending, isEmpty);
    });

    test('Genug exakte Darts: nur sie zählen; sonst alle, dann „geschätzt“', () {
      final a = ScatterReport.build([...cross(t20, 30), ...cross(t20, 20, t: 30, exact: false)]);
      expect(a[t20]!.darts, 30);
      expect(a[t20]!.exact, isTrue);
      expect(a[t20]!.offset.t, closeTo(0, 1e-6));
      final b = ScatterReport.build([...cross(t20, 10), ...cross(t20, 25, exact: false)]);
      expect(b[t20]!.darts, 35);
      expect(b[t20]!.exact, isFalse);
    });

    test('Tendenz insgesamt nach Darts gewichtet', () {
      final r = ScatterReport.build([...cross(t20, 90, t: -6, r: -6), ...cross(d16, 30, t: 6, r: -6)], positioned: 200);
      final o = r.overall!;
      expect(o.darts, 120);
      expect(o.offsetT, closeTo(-3, 1e-6));
      expect(o.offsetR, closeTo(-6, 1e-6));
      expect(r.positioned, 200);
      expect(r.assigned, 120);
      expect(r.fields.first.field, t20, reason: 'meiste Darts zuerst');
    });
  });

  group('Tipps', () {
    ScatterShape shape(Segment field, {double t = 0, double r = 0, double sdT = 15, double sdR = 15, int n = 200}) =>
        ScatterShape(field: field, offsetT: t, offsetR: r, sdT: sdT, sdR: sdR, darts: n);
    List<ScatterTipKind> kinds(ScatterShape s) => [for (final t in scatterTips(s)) t.kind];

    test('Eng gruppiert: weiter so, oder bei Abweichung Zielpunkt verschieben', () {
      expect(kinds(shape(t20, sdT: 8, sdR: 7)), [ScatterTipKind.steady]);
      expect(kinds(shape(t20, t: -6, sdT: 8, sdR: 7)), [ScatterTipKind.shiftAim]);
    });

    test('Feld oben zu tief: Wurf evtl. zu flach; zu hoch: evtl. zu viel Kraft', () {
      expect(kinds(shape(t20, r: -8)).first, ScatterTipKind.tooFlat);
      expect(kinds(shape(t20, r: 8)).first, ScatterTipKind.tooSteep);
    });

    test('Feld unten: Richtung Bull bzw. außen statt flach/steil', () {
      expect(kinds(shape(t3, r: -8)).first, ScatterTipKind.inside);
      expect(kinds(shape(t3, r: 8)).first, ScatterTipKind.outside);
    });

    test('Seitlich: Richtung der Nachbarzahl, beim Bull links/rechts', () {
      expect(scatterTips(shape(t20, t: -8)).first, const ScatterTip(ScatterTipKind.drift, toward: 5));
      expect(scatterTips(shape(t20, t: 8)).first, const ScatterTip(ScatterTipKind.drift, toward: 1, right: true));
      expect(scatterTips(shape(Segment.bull, t: 8)).first, const ScatterTip(ScatterTipKind.drift, right: true));
    });

    test('Größere Abweichung zuerst, höchstens zwei Tipps', () {
      final tips = scatterTips(shape(t20, t: -10, r: -6, sdT: 22, sdR: 14));
      expect(tips.length, maxScatterTips);
      expect(tips.first.kind, ScatterTipKind.drift);
      expect(tips.last.kind, ScatterTipKind.tooFlat);
    });

    test('Große Streuung zuerst', () {
      expect(kinds(shape(t20, r: -10, sdT: 26, sdR: 25)), [ScatterTipKind.wideOverall, ScatterTipKind.tooFlat]);
    });

    test('Form der Streuung in Achsen der Scheibe', () {
      expect(kinds(shape(t20, sdT: 20, sdR: 12)), [ScatterTipKind.wideSideways]);
      expect(kinds(shape(t20, sdT: 12, sdR: 20)), [ScatterTipKind.wideHeight]);
      // D11 liegt seitlich: „seitlich im Feld“ ist an der Scheibe senkrecht.
      expect(kinds(shape(d11, sdT: 20, sdR: 12)), [ScatterTipKind.wideHeight]);
      expect(kinds(shape(d11, sdT: 12, sdR: 20)), [ScatterTipKind.wideSideways]);
    });

    test('Mittig ohne Auffälligkeit: Gruppierung enger bekommen', () {
      expect(kinds(shape(t20, t: 1, r: -1)), [ScatterTipKind.tighten]);
    });

    test('Mittig hängt von Streuung und Menge ab', () {
      expect(shape(t20, r: -4, sdT: 15, sdR: 15, n: 400).centered, isFalse);
      expect(shape(t20, r: -4, sdT: 25, sdR: 25, n: 400).centered, isTrue);
      expect(shape(t20, r: -4, sdT: 12, sdR: 12, n: 30).centered, isTrue, reason: 'zu wenige Darts für 4 mm');
    });
  });

  group('StatsCalculator', () {
    /// T20-Training (10 Aufnahmen): Darts links unten um T20.
    (SessionRow, List<ThrowRow>) t20Practice({String source = 'simulator'}) {
      final s = session('target_practice', config: const {'number': 20, 'visits': 10});
      final rows = [
        for (var i = 0; i < 30; i++)
          row(
            p: near(t20, t: -4 + [6.0, -6.0, 0.0, 0.0][i % 4], r: -5 + [0.0, 0.0, 6.0, -6.0][i % 4]),
            sessionId: s.id,
            gameId: s.gameId,
            seq: i,
            visit: i ~/ 3,
            source: source,
          ),
      ];
      return (s, rows);
    }

    test('Training exakt, Online geschätzt, manuell nie; Auswahl Training/Match', () {
      final (a, ra) = t20Practice();
      final (b, rb) = t20Practice();
      final (m, rm) = t20Practice(source: 'manual');
      final live = session('autodarts_live');
      final rl = [
        for (var i = 0; i < 36; i++)
          row(p: near(t19, t: [8.0, -8.0, 0.0][i % 3], r: 2), sessionId: live.id, gameId: live.gameId, seq: i, visit: i ~/ 3),
      ];
      final calc = StatsCalculator(sessions: [a, b, m, live], throws: [...ra, ...rb, ...rm, ...rl], now: now);

      final all = calc.scatterReport(StatsPeriod.week);
      expect(all.positioned, 96, reason: 'manuelle Darts haben keine Position');
      expect(all[t20]!.darts, 60);
      expect(all[t20]!.exact, isTrue);
      expect(all[t20]!.offset.t, closeTo(-4, 1e-6));
      expect(all[t20]!.direction, ScatterDirection.downLeft);
      expect(all[t19]!.exact, isFalse);
      expect(identical(calc.scatterReport(StatsPeriod.week), all), isTrue, reason: 'zwischengespeichert');

      final training = calc.scatterReport(StatsPeriod.week, scope: ScatterScope.training);
      expect([for (final f in training.fields) f.field], [t20]);
      final match = calc.scatterReport(StatsPeriod.week, scope: ScatterScope.match);
      expect([for (final f in match.fields) f.field], [t19]);
      expect(match.positioned, 36);

      expect(calc.scatterReport(StatsPeriod.week, gameId: 'cricket').isEmpty, isTrue);
    });

    test('Übernimmt die Darts unveränderter Sessions aus dem vorigen Rechner', () {
      final (a, ra) = t20Practice();
      final first = StatsCalculator(sessions: [a], throws: ra, now: now);
      final darts = first.scatterOf(a).darts;
      final second = StatsCalculator(sessions: [a], throws: ra, now: now, previous: first, unchanged: {a.id});
      expect(identical(second.scatterOf(a).darts, darts), isTrue);
    });
  });
}
