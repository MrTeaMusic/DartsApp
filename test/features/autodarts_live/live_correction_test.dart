import 'package:dartlab/features/autodarts_live/domain/live_recorder.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 14, 20);

Segment seg(String name) => Segment.tryParse(name)!;

DartThrow board(String name, [int seconds = 0]) => DartThrow(
      segment: seg(name),
      position: const BoardPoint(0.1, 0.2),
      timestamp: t0.add(Duration(seconds: seconds)),
      source: DartSourceKind.autodartsLocal,
      raw: const {'x': 1},
    );

List<String> names(Iterable<DartThrow> darts) => [for (final x in darts) x.segment.name];

/// Wirft [visits] (je Aufnahme ein Takeout), die letzte bleibt offen, wenn
/// [openLast] gesetzt ist.
LiveRecorder recorded(List<List<String>> visits, {bool openLast = false}) {
  final r = LiveRecorder();
  var sec = 0;
  for (final (i, v) in visits.indexed) {
    for (final (j, n) in v.indexed) {
      r.apply(DartThrown(board(n, sec++), index: j));
    }
    if (!(openLast && i == visits.length - 1)) r.apply(TakeoutFinished(t0));
  }
  return r;
}

void main() {
  group('von Hand korrigieren', () {
    test('Dart einer abgeschlossenen Aufnahme ändern: von Hand gesetzt, ohne Position, Zeit bleibt', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
        ['S1', 'S5', 'S20'],
      ]);
      final up = r.correctDart(0, 1, seg('S19'));
      expect(up.rewritten, isTrue);
      expect(names(r.closedVisits[0]), ['T20', 'S19', 'T20']);
      final fixed = r.closedVisits[0][1];
      expect(fixed.source, DartSourceKind.manual);
      expect(LiveRecorder.isManual(fixed), isTrue);
      expect(fixed.position, isNull);
      expect(fixed.raw, isNull);
      expect(fixed.timestamp, t0.add(const Duration(seconds: 1)));
      // Die anderen Darts behalten Position und Quelle.
      final other = r.closedVisits[0][0];
      expect(other.position, const BoardPoint(0.1, 0.2));
      expect(other.source, DartSourceKind.autodartsLocal);
      expect(LiveRecorder.isManual(other), isFalse);
      expect(r.dartCount, 6);
    });

    test('dasselbe Feld oder eine falsche Stelle ändern nichts', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
      ]);
      expect(r.correctDart(0, 0, seg('T20')).changed, isFalse);
      expect(r.closedVisits[0][0].source, DartSourceKind.autodartsLocal, reason: 'kein Festhalten ohne Änderung');
      expect(r.correctDart(0, 3, seg('S1')).changed, isFalse);
      expect(r.correctDart(1, 0, seg('S1')).changed, isFalse);
      expect(r.correctDart(-1, 0, seg('S1')).changed, isFalse);
    });

    test('Dart der laufenden Aufnahme ändern', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
        ['S1', 'S5'],
      ], openLast: true);
      expect(r.closedCount, 1);
      r.correctDart(1, 1, seg('D10'));
      expect(names(r.currentVisit), ['S1', 'D10']);
    });

    test('Dart entfernen: Aufnahme wird kürzer, der letzte Dart nimmt die Aufnahme mit', () {
      final r = recorded([
        ['T20', 'T20'],
        ['S1', 'S5', 'S20'],
        ['D1'],
      ]);
      r.removeDart(1, 0);
      expect(r.closedVisits.map(names), [
        ['T20', 'T20'],
        ['S5', 'S20'],
        ['D1'],
      ]);
      r.removeDart(2, 0);
      expect(r.closedVisits.map(names), [
        ['T20', 'T20'],
        ['S5', 'S20'],
      ], reason: 'leere Aufnahme verschwindet');
      expect(r.darts.map((x) => x.visitIndex), [0, 0, 1, 1]);
      expect(r.removeDart(5, 0).changed, isFalse);
    });

    test('Dart ergänzen: ans Ende der Aufnahme, höchstens drei, Zeit vom letzten Dart', () {
      final r = recorded([
        ['T20', 'T20'],
        ['S1', 'S5', 'S20'],
      ]);
      expect(r.addDart(1, seg('S3'), t0).changed, isFalse, reason: 'schon drei Darts');
      final up = r.addDart(0, seg('T19'), t0.add(const Duration(hours: 1)));
      expect(up.rewritten, isTrue);
      expect(names(r.closedVisits[0]), ['T20', 'T20', 'T19']);
      final added = r.closedVisits[0][2];
      expect(added.source, DartSourceKind.manual);
      expect(added.position, isNull);
      expect(added.timestamp, t0.add(const Duration(seconds: 1)), reason: 'Zeit des letzten Darts der Aufnahme');
      expect(r.dartCount, 6);
      expect(r.darts.map((x) => x.visitIndex), [0, 0, 0, 1, 1, 1]);
    });

    test('Dart in die laufende Aufnahme ergänzen, auch in eine leere', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
      ]);
      expect(r.currentVisit, isEmpty);
      final late = t0.add(const Duration(minutes: 3));
      r.addDart(1, seg('S5'), late);
      expect(names(r.currentVisit), ['S5']);
      expect(r.currentVisit.single.timestamp, late);
      expect(r.lastDartAt, late);
      r.addDart(1, seg('S6'), late);
      expect(names(r.currentVisit), ['S5', 'S6']);
      expect(r.addDart(7, seg('S6'), late).changed, isFalse);
    });

    test('Aufnahme löschen: spätere rücken nach, die laufende wird geleert', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
        ['S1', 'S5', 'S20'],
        ['D1', 'D2'],
      ], openLast: true);
      r.removeVisit(0);
      expect(r.closedVisits.map(names), [
        ['S1', 'S5', 'S20'],
      ]);
      expect(r.darts.map((x) => x.visitIndex), [0, 0, 0, 1, 1]);
      r.removeVisit(1);
      expect(r.currentVisit, isEmpty);
      expect(r.removeVisit(1).changed, isFalse, reason: 'leere laufende Aufnahme');
      expect(r.removeVisit(4).changed, isFalse);
      expect(r.dartCount, 3);
    });

    test('Zeit des letzten Darts folgt den Änderungen; leer = keine Pause, keine neue Session', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
        ['S1'],
      ]);
      expect(r.lastDartAt, t0.add(const Duration(seconds: 3)));
      r.removeVisit(1);
      expect(r.lastDartAt, t0.add(const Duration(seconds: 2)));
      r.removeVisit(0);
      expect(r.dartCount, 0);
      expect(r.lastDartAt, isNull);
      // Nach langer Zeit gibt es keine Pause-Trennung und keine zweite Session.
      r.apply(DartThrown(board('S20', 4000), index: 0));
      expect(r.sessionCount, 1);
      expect(r.stats.darts, 1);
    });

    test('Kennzahlen folgen den Korrekturen', () {
      final r = recorded([
        ['T20', 'T20', 'T20'],
      ]);
      expect(r.stats.points, 180);
      r.correctDart(0, 2, seg('MISS'));
      expect(r.stats.points, 120);
      expect(r.stats.misses, 1);
    });
  });

  group('festgehaltene Darts und Meldungen des Boards', () {
    test('Korrektur vom Board überschreibt keinen von Hand gesetzten Dart', () {
      final r = recorded([
        ['T20', 'T5'],
      ], openLast: true);
      r.correctDart(0, 1, seg('S20'));
      expect(r.apply(DartCorrected(1, board('S1'))).changed, isFalse);
      expect(names(r.currentVisit), ['T20', 'S20']);
      // Ein nicht festgehaltener Dart folgt weiter dem Board.
      expect(r.apply(DartCorrected(0, board('D20'))).rewritten, isTrue);
      expect(names(r.currentVisit), ['D20', 'S20']);
    });

    test('Rückgängig vom Board entfernt keinen von Hand gesetzten Dart', () {
      final r = recorded([
        ['T20', 'T5'],
      ], openLast: true);
      r.correctDart(0, 1, seg('S20'));
      expect(r.apply(DartUndone(t0)).changed, isFalse);
      expect(names(r.currentVisit), ['T20', 'S20']);
      // Ohne festgehaltenen letzten Dart gilt Rückgängig wie immer.
      final r2 = recorded([
        ['T20', 'T5'],
      ], openLast: true);
      r2.correctDart(0, 0, seg('S20'));
      expect(r2.apply(DartUndone(t0)).rewritten, isTrue);
      expect(names(r2.currentVisit), ['S20']);
    });

    test('Dart gelöscht oder ergänzt: laufende Aufnahme ignoriert Korrektur und Rückgängig des Boards', () {
      final r = recorded([
        ['T20', 'T5', 'S1'],
      ], openLast: true);
      r.removeDart(0, 0);
      expect(names(r.currentVisit), ['T5', 'S1']);
      // Die Stellen des Boards passen nicht mehr.
      expect(r.apply(DartCorrected(1, board('D1'))).changed, isFalse);
      expect(r.apply(DartUndone(t0)).changed, isFalse);
      expect(names(r.currentVisit), ['T5', 'S1']);
      // Takeout beendet die Aufnahme; die nächste folgt dem Board wieder.
      r.apply(TakeoutFinished(t0));
      r.apply(DartThrown(board('S7', 10), index: 0));
      r.apply(DartThrown(board('S8', 11), index: 1));
      expect(r.apply(DartCorrected(1, board('S9'))).rewritten, isTrue);
      expect(names(r.currentVisit), ['S7', 'S9']);
    });

    test('nach dem Umbauen zählt die Stelle des Boards nicht mehr, nur Takeout und drei Darts schließen', () {
      final r = recorded([
        ['T20', 'T5'],
      ], openLast: true);
      r.addDart(0, seg('S1'), t0);
      expect(names(r.currentVisit), ['T20', 'T5', 'S1']);
      // Das Board meldet Stelle 1, hier ist die Aufnahme schon voll: neue Aufnahme.
      r.apply(DartThrown(board('S2', 9), index: 1));
      expect(r.closedVisits.map(names), [
        ['T20', 'T5', 'S1'],
      ]);
      expect(names(r.currentVisit), ['S2']);

      // Eine Aufnahme mit gelöschtem Dart schließt nicht wegen einer niedrigen Stelle.
      final q = recorded([
        ['T20', 'T5'],
      ], openLast: true);
      q.removeDart(0, 0);
      q.apply(DartThrown(board('S2', 9), index: 1));
      expect(q.closedCount, 0);
      expect(names(q.currentVisit), ['T5', 'S2']);
    });

    test('leere laufende Aufnahme nach Löschen: Board gilt wieder', () {
      final r = recorded([
        ['T20'],
      ], openLast: true);
      r.removeDart(0, 0);
      r.apply(DartThrown(board('S2', 9), index: 0));
      r.apply(DartThrown(board('S3', 10), index: 1));
      expect(r.apply(DartCorrected(1, board('S4'))).rewritten, isTrue);
      expect(names(r.currentVisit), ['S2', 'S4']);
    });

    test('abgeschlossene Aufnahmen bleiben für das Board unantastbar, Handkorrektur geht', () {
      final r = recorded([
        ['T20', 'T5', 'S1'],
      ]);
      expect(r.apply(DartCorrected(0, board('D1'))).changed, isFalse);
      expect(r.apply(DartUndone(t0)).changed, isFalse);
      expect(r.correctDart(0, 0, seg('D1')).changed, isTrue);
    });
  });

  group('Leg-Markierungen verschieben sich mit', () {
    const lost = LegMarkKind.lost;
    const restart = LegMarkKind.restart;

    test('Entfernen vor der Marke rückt sie vor, dahinter bleibt sie', () {
      final marks = [(at: 6, kind: lost), (at: 9, kind: restart)];
      expect(marksAfterRemoval(marks, from: 2, count: 1), [(at: 5, kind: lost), (at: 8, kind: restart)]);
      // Der Dart direkt vor der Marke (Stelle 5) geht: die Marke steht danach bei 5.
      expect(marksAfterRemoval(marks, from: 5, count: 1).first.at, 5);
      // Dart hinter der Marke (Stelle 6) ändert sie nicht.
      expect(marksAfterRemoval(marks, from: 6, count: 1).first.at, 6);
      expect(marksAfterRemoval(marks, from: 7, count: 1), [(at: 6, kind: lost), (at: 8, kind: restart)]);
    });

    test('Aufnahme löschen: Marken in der Lücke landen an der Lücke', () {
      final marks = [(at: 2, kind: lost), (at: 4, kind: lost), (at: 8, kind: restart)];
      expect(marksAfterRemoval(marks, from: 3, count: 3), [(at: 2, kind: lost), (at: 3, kind: lost), (at: 5, kind: restart)]);
    });

    test('Einfügen: davor rückt die Marke, genau an der Stelle je nach Aufnahme', () {
      final marks = [(at: 3, kind: lost), (at: 6, kind: lost)];
      // Ans Ende einer abgeschlossenen Aufnahme (Stelle 3): der Dart war noch vor dem Leg-Ende dran.
      expect(marksAfterInsert(marks, at: 3, beforeMarkAtPosition: true), [(at: 4, kind: lost), (at: 7, kind: lost)]);
      // Wie ein neuer Dart des Boards in die laufende Aufnahme: nach der Marke.
      expect(marksAfterInsert(marks, at: 3, beforeMarkAtPosition: false), [(at: 3, kind: lost), (at: 7, kind: lost)]);
      expect(marksAfterInsert(marks, at: 7, beforeMarkAtPosition: true), marks);
    });

    LiveX01 replay(List<List<String>> visits, List<LegMark> marks) => LiveX01.replay(
          const LiveX01Config(startScore: 301),
          [
            for (final v in visits) [for (final n in v) seg(n)],
          ],
          marks,
          visitOpen: false,
        );

    test('Leg verloren bleibt nach Dart-Löschen im selben Moment', () {
      // Leg 1: zwei Aufnahmen (T20 x3, S20 x3), dann „Leg verloren“, Leg 2 beginnt.
      final visits = [
        ['T20', 'T20', 'T20'],
        ['S20', 'S20', 'S20'],
        ['T19', 'S1', 'S1'],
      ];
      final base = replay(visits, [(at: 6, kind: lost)]);
      expect(base.legsLost, 1);
      expect(base.legs.single.darts, 6);
      expect(base.remaining, 301 - 59);

      // Dart 1 der ersten Aufnahme löschen: Leg 1 hat 5 Darts, Marke bei 5.
      final fewer = [
        ['T20', 'T20'],
        ['S20', 'S20', 'S20'],
        ['T19', 'S1', 'S1'],
      ];
      final marks = marksAfterRemoval([(at: 6, kind: lost)], from: 2, count: 1);
      final after = replay(fewer, marks);
      expect(after.legsLost, 1);
      expect(after.legs.single.darts, 5);
      expect(after.remaining, 301 - 59, reason: 'Leg 2 unverändert');

      // Ohne Verschieben würde die Marke einen Dart des neuen Legs ins alte ziehen.
      final wrong = replay(fewer, [(at: 6, kind: lost)]);
      expect(wrong.legs.single.darts, 6);
      expect(wrong.remaining, isNot(after.remaining));
    });

    test('Dart ans Ende der Aufnahme vor dem Leg-Ende gehört noch ins alte Leg', () {
      final visits = [
        ['T20', 'T20', 'T20'],
        ['S20', 'S20'],
        ['T19', 'S1', 'S1'],
      ];
      // „Leg verloren“ nach zwei Aufnahmen (5 Darts).
      final marks = [(at: 5, kind: lost)];
      final before = replay(visits, marks);
      expect(before.legs.single.darts, 5);
      final fixed = [
        visits[0],
        ['S20', 'S20', 'S5'],
        visits[2],
      ];
      final after = replay(fixed, marksAfterInsert(marks, at: 5, beforeMarkAtPosition: true));
      expect(after.legs.single.darts, 6);
      expect(after.remaining, before.remaining, reason: 'Leg 2 unverändert');
    });
  });
}
