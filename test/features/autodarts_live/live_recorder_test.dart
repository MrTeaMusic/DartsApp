import 'package:dartlab/features/autodarts_live/domain/live_recorder.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/autodarts_state_mapper.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 14, 20);

DartThrow d(String name, [Duration after = Duration.zero]) =>
    DartThrow(segment: Segment.tryParse(name)!, timestamp: t0.add(after), source: DartSourceKind.autodartsLocal);

List<String> names(Iterable<DartThrow> darts) => [for (final x in darts) x.segment.name];

Map<String, Object?> state(List<String> throws, {String event = 'Throw detected'}) => {
      'connected': true,
      'running': true,
      'status': 'Throw',
      'event': event,
      'numThrows': throws.length,
      if (throws.isNotEmpty)
        'throws': [
          for (final n in throws)
            {
              'segment': {
                'name': n,
                'number': Segment.tryParse(n)!.number,
                'multiplier': Segment.tryParse(n)!.multiplier,
                'bed': Segment.tryParse(n)!.isMiss ? 'Outside' : 'Single',
              },
              'coords': {'x': 0.0, 'y': 0.5},
            },
        ],
    };

void main() {
  group('Aufnahmen', () {
    test('Takeout beendet die Aufnahme, auch nach weniger als drei Darts', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('T20'), index: 0));
      r.apply(DartThrown(d('T20'), index: 1));
      expect(r.apply(TakeoutFinished(t0)).visitClosed, isTrue);
      r.apply(DartThrown(d('S5'), index: 0));
      expect(r.closedVisits.map(names), [
        ['T20', 'T20'],
      ]);
      expect(names(r.currentVisit), ['S5']);
      expect(r.darts.map((x) => x.visitIndex), [0, 0, 1]);
    });

    test('nach drei Darts ohne Takeout beginnt mit dem vierten eine neue Aufnahme', () {
      final r = LiveRecorder();
      for (final n in ['T20', 'S20', 'S1']) {
        r.apply(DartThrown(d(n)));
      }
      final u = r.apply(DartThrown(d('T19')));
      expect(u.visitClosed, isTrue);
      expect(r.closedVisits.single.length, 3);
      expect(names(r.currentVisit), ['T19']);
    });

    test('Stelle 0 bei laufender Aufnahme (z. B. nach Neuverbindung) beginnt eine neue Aufnahme', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('T20'), index: 0));
      r.apply(DartThrown(d('T20'), index: 1));
      r.apply(DartThrown(d('S3'), index: 0));
      expect(r.closedVisits.map(names), [
        ['T20', 'T20'],
      ]);
      expect(names(r.currentVisit), ['S3']);
    });

    test('Reset am Board schließt die Aufnahme, die Darts bleiben', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('D16'), index: 0));
      r.apply(TurnReset(t0));
      expect(r.dartCount, 1);
      expect(r.currentVisit, isEmpty);
    });
  });

  group('Pause', () {
    test('nach 20 Minuten ohne Dart beginnt eine neue Session', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('T20'), index: 0));
      r.apply(DartThrown(d('S20', const Duration(seconds: 3)), index: 1));
      final u = r.apply(DartThrown(d('S1', const Duration(minutes: 21)), index: 2));
      expect(u.closedSession, isNotNull);
      expect(names(u.closedSession!.map((x) => x.dart)), ['T20', 'S20']);
      expect(names(r.darts.map((x) => x.dart)), ['S1']);
      expect(u.added!.visitIndex, 0);
      expect(r.sessionCount, 2);
    });

    test('kürzere Pausen bleiben in derselben Session', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('T20')));
      final u = r.apply(DartThrown(d('S20', const Duration(minutes: 19))));
      expect(u.closedSession, isNull);
      expect(r.sessionCount, 1);
    });

    test('Grenze ist einstellbar', () {
      final r = LiveRecorder(pauseLimit: const Duration(minutes: 1));
      r.apply(DartThrown(d('T20')));
      expect(r.apply(DartThrown(d('S20', const Duration(minutes: 1)))).closedSession, isNotNull);
    });
  });

  group('Korrekturen', () {
    test('geänderter und entfernter Dart werden in der laufenden Aufnahme übernommen', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('T20'), index: 0));
      r.apply(DartThrown(d('S5'), index: 1));
      expect(r.apply(DartCorrected(1, d('S1'))).rewritten, isTrue);
      expect(names(r.currentVisit), ['T20', 'S1']);
      expect(r.apply(DartUndone(t0)).rewritten, isTrue);
      expect(names(r.currentVisit), ['T20']);
    });

    test('Korrektur außerhalb der laufenden Aufnahme wird ignoriert', () {
      final r = LiveRecorder();
      r.apply(DartThrown(d('T20'), index: 0));
      r.apply(TakeoutFinished(t0));
      expect(r.apply(DartCorrected(0, d('S1'))).changed, isFalse);
      expect(r.apply(DartUndone(t0)).changed, isFalse);
      expect(r.closedVisits.map(names), [
        ['T20'],
      ]);
    });

    test('über den Mapper: neu aufgebaute Liste wird gespiegelt (ungeprüftes Format, defensiv)', () {
      final mapper = AutodartsStateMapper(clock: () => t0);
      final r = LiveRecorder();
      void feed(Map<String, Object?> s) {
        for (final e in mapper.update(s)) {
          r.apply(e);
        }
      }

      feed(state([], event: 'Takeout finished')); // Ausgangslage
      feed(state(['T20']));
      feed(state(['T20', 'S5']));
      feed(state(['T20', 'S5', 'S1']));
      // Board Manager meldet den mittleren Dart als entfernt: Liste rückt auf.
      feed(state(['T20', 'S1']));
      expect(names(r.currentVisit), ['T20', 'S1']);
      // Feld des ersten Darts korrigiert.
      feed(state(['T5', 'S1']));
      expect(names(r.currentVisit), ['T5', 'S1']);
      feed(state([], event: 'Takeout finished'));
      expect(r.closedVisits.map(names), [
        ['T5', 'S1'],
      ]);
    });
  });

  group('Kennzahlen', () {
    test('Rohschnitt, Bänder und Verteilung', () {
      LiveDart l(String n) => (segment: Segment.tryParse(n)!, position: null);
      final s = LiveStats.of([
        [l('T20'), l('T20'), l('T20')],
        [l('T20'), l('T20'), l('S20')],
        [l('S20'), l('MISS'), l('D10')],
      ]);
      expect(s.darts, 9);
      expect(s.points, 180 + 140 + 40);
      expect(s.rawAverage, closeTo(120, 0.001));
      expect((s.count180, s.count140, s.count100), (1, 1, 0));
      expect((s.triples, s.doubles, s.singles, s.misses), (5, 1, 2, 1));
      expect(s.missShare, closeTo(1 / 9, 1e-9));
      // Fehlwurf ohne Koordinaten: kein Punkt in der Heatmap.
      expect(s.heat.length, 8);
      final m = s.toResult().metrics;
      expect(m.containsKey('average'), isFalse, reason: 'kein offizieller X01-Average');
      expect(m.containsKey('first9'), isFalse);
      expect(m['rawAverage'], 120);
    });
  });

  group('X01 mitzählen', () {
    List<List<Segment>> v(List<List<String>> visits) => [
          for (final x in visits) [for (final n in x) Segment.tryParse(n)!],
        ];

    test('Leg mit Checkout: Average, First 9 und Checkout-Quote', () {
      final x = LiveX01.replay(
        const LiveX01Config(),
        v([
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'T20'],
          ['T20', 'T19', 'D12'],
        ]),
        const [],
        visitOpen: false,
      );
      expect(x.legsWon, 1);
      expect(x.legs.single.checkout, 141);
      expect(x.remaining, 501);
      expect(x.darts, 9);
      expect(x.average, closeTo(167, 0.001));
      expect(x.first9, closeTo(167, 0.001));
      expect(x.checkoutDarts, 1);
      expect(x.checkoutRate, 1);
      expect((x.count180, x.count140), (2, 1));
      final r = x.result({'rawAverage': 167});
      expect(r.metrics['legsWon'], 1);
      expect(r.metrics['highestFinish'], 141);
      expect(r.metrics['rawAverage'], 167);
    });

    test('Bust setzt den Rest zurück, weitere Darts der Aufnahme zählen nicht', () {
      final x = LiveX01.replay(
        const LiveX01Config(startScore: 301),
        v([
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'S1'], // 121 - 60 = 61, - 60 = 1: Bust beim zweiten Dart
          ['S20'],
        ]),
        const [],
      );
      expect(x.busts, 1);
      expect(x.counted, [true, true, true, true, true, false, true]);
      expect(x.remaining, 121 - 20);
      // Bust-Aufnahme zählt mit 0 Punkten: (180 + 0 + 20) / 6 Darts.
      expect(x.average, closeTo(200 / 6 * 3, 0.001));
    });

    test('Rest und Vorschlag in der laufenden Aufnahme', () {
      final x = LiveX01.replay(
        const LiveX01Config(startScore: 101),
        v([
          ['T20'],
        ]),
        const [],
      );
      expect(x.remaining, 41);
      expect(x.dartsLeft, 2);
      expect(x.suggestion, isNotNull);
      expect(x.suggestion!.last.isDouble, isTrue);
    });

    test('Leg verloren und Leg neu starten', () {
      final visits = v([
        ['T20', 'T20', 'T20'],
        ['S20', 'S20', 'S20'],
        ['T20'],
      ]);
      final lost = LiveX01.replay(const LiveX01Config(), visits, const [(at: 6, kind: LegMarkKind.lost)]);
      expect(lost.legs.single.won, isFalse);
      expect(lost.legs.single.darts, 6);
      expect(lost.legsLost, 1);
      expect(lost.remaining, 441);
      final restart = LiveX01.replay(const LiveX01Config(), visits, const [(at: 6, kind: LegMarkKind.restart)]);
      expect(restart.legs, isEmpty);
      expect(restart.remaining, 441);
      // Markierung ohne Darts im Leg ändert nichts.
      final empty = LiveX01.replay(const LiveX01Config(), visits, const [(at: 0, kind: LegMarkKind.lost)]);
      expect(empty.legs, isEmpty);
    });

    test('Straight-Out: Checkout mit Single', () {
      final x = LiveX01.replay(
        const LiveX01Config(startScore: 301, outMode: OutMode.straight),
        v([
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'S1'],
        ]),
        const [],
        visitOpen: false,
      );
      expect(x.legsWon, 1);
    });
  });

  test('Mapper: Bull als Zahl 50 (nicht am echten Board gesehen)', () {
    expect(AutodartsStateMapper.parseSegment({'name': '50', 'number': 50, 'multiplier': 1}), Segment.bull);
  });
}
