import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/autodarts_state_mapper.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> throwJson(String name, int number, String bed, int multiplier, {double? x, double? y}) => {
      'segment': {'name': name, 'number': number, 'bed': bed, 'multiplier': multiplier},
      if (x != null) 'coords': {'x': x, 'y': y},
    };

Map<String, Object?> state(List<Map<String, Object?>> throws, {String status = 'Throw', String? event}) => {
      'connected': true,
      'running': true,
      'status': status,
      'event': event ?? status,
      'numThrows': throws.length,
      'throws': throws,
    };

void main() {
  late AutodartsStateMapper mapper;
  setUp(() => mapper = AutodartsStateMapper(clock: () => DateTime(2026, 10, 11)));

  test('erster Zustand ist Ausgangslage und meldet keine alten Darts', () {
    expect(mapper.update(state([throwJson('T20', 20, 'Triple', 3)])), isEmpty);
  });

  test('neue Darts werden mit Segment, Index und Koordinaten gemeldet', () {
    mapper.update(state([]));
    final events = mapper.update(state([throwJson('T20', 20, 'Triple', 3, x: 0.01, y: 0.61)]));
    expect(events, hasLength(1));
    final thrown = events.single as DartThrown;
    expect(thrown.index, 0);
    expect(thrown.dart.segment, Segment.triple(20));
    expect(thrown.dart.position, const BoardPoint(0.01, 0.61));
    expect(thrown.dart.source, DartSourceKind.autodartsLocal);
    expect(thrown.dart.raw?['segment'], isA<Map<String, Object?>>());

    final next = mapper.update(state([
      throwJson('T20', 20, 'Triple', 3),
      throwJson('S5', 5, 'SingleInner', 1),
      throwJson('25', 25, 'Single', 1),
    ]));
    expect(next.map((e) => (e as DartThrown).dart.segment), [Segment.single(5, inner: true), Segment.outerBull]);
    expect(next.map((e) => (e as DartThrown).index), [1, 2]);
  });

  test('Bull, Miss und Name als Rückfall', () {
    expect(AutodartsStateMapper.parseSegment({'name': 'Bull', 'number': 25, 'bed': 'Double', 'multiplier': 2}), Segment.bull);
    expect(AutodartsStateMapper.parseSegment({'name': 'M7', 'number': 7, 'bed': 'Outside', 'multiplier': 0}), Segment.miss);
    expect(AutodartsStateMapper.parseSegment({'name': 'D16'}), Segment.double(16));
    expect(AutodartsStateMapper.parseSegment('T19'), Segment.triple(19));
    expect(AutodartsStateMapper.parseSegment({'number': '18', 'multiplier': '2'}), Segment.double(18));
    expect(AutodartsStateMapper.parseSegment({'foo': 1}), isNull);
  });

  test('Takeout: gestartet, dann Board leer', () {
    mapper.update(state([]));
    mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)]));
    final started = mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)], status: 'Takeout in progress'));
    expect(started.single, isA<TakeoutStarted>());
    final finished = mapper.update(state([], status: 'Throw', event: 'Takeout finished'));
    expect(finished.single, isA<TakeoutFinished>());
    // Danach zählen neue Darts wieder ab Index 0.
    final again = mapper.update(state([throwJson('S2', 2, 'SingleOuter', 1)]));
    expect((again.single as DartThrown).index, 0);
  });

  test('Board wird ohne Takeout-Meldung leer: gilt als Takeout beendet', () {
    mapper.update(state([]));
    mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)]));
    expect(mapper.update(state([])).single, isA<TakeoutFinished>());
    expect(mapper.update(state([])), isEmpty);
  });

  test('Korrektur eines Darts', () {
    mapper.update(state([]));
    mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)]));
    final events = mapper.update(state([throwJson('D1', 1, 'Double', 2)]));
    final corrected = events.single as DartCorrected;
    expect(corrected.index, 0);
    expect(corrected.dart.segment, Segment.double(1));
  });

  test('Dart entfernt (Liste wird kürzer, aber nicht leer)', () {
    mapper.update(state([]));
    mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1), throwJson('S2', 2, 'SingleOuter', 1)]));
    expect(mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)])).single, isA<DartUndone>());
  });

  test('Manual reset', () {
    mapper.update(state([]));
    mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)]));
    final events = mapper.update(state([], status: 'Throw', event: 'Manual reset'));
    expect(events.single, isA<TurnReset>());
  });

  test('neuer Dart während Takeout beendet den Takeout', () {
    mapper.update(state([]));
    final first = mapper.update(state([throwJson('S1', 1, 'SingleOuter', 1)], status: 'Takeout in progress'));
    expect(first.map((e) => e.runtimeType), [DartThrown, TakeoutStarted]);
    final events = mapper.update(state([
      throwJson('S1', 1, 'SingleOuter', 1),
      throwJson('S2', 2, 'SingleOuter', 1),
    ]));
    expect(events.map((e) => e.runtimeType), [TakeoutFinished, DartThrown]);
  });

  test('unbekannte Daten erzeugen Hinweise statt Absturz', () {
    mapper.update(state([]));
    final events = mapper.update({
      'throws': [
        {'segment': {'weird': true}},
        'kein Objekt',
      ],
    });
    expect(events, isEmpty);
    expect(mapper.warnings, hasLength(2));
    expect(mapper.update({'throws': 'kaputt'}), isEmpty);
    expect(mapper.warnings, hasLength(3));
  });

  test('ohne "throws"-Feld werden nur Status ausgewertet', () {
    mapper.update(state([]));
    expect(mapper.update({'status': 'Takeout started', 'numThrows': 3}).single, isA<TakeoutStarted>());
    expect(mapper.update({'status': 'Throw', 'numThrows': 0}).single, isA<TakeoutFinished>());
  });
}
