import 'dart:async';
import 'dart:math' as math;

import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/manual_source.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SimulatorSource', () {
    late SimulatorSource source;
    late List<DartEvent> events;
    late StreamSubscription<DartEvent> sub;

    setUp(() {
      source = SimulatorSource(random: math.Random(1), takeoutDelay: Duration.zero);
      events = [];
      sub = source.events.listen(events.add);
    });
    tearDown(() async {
      await sub.cancel();
      await source.dispose();
    });

    test('start meldet bereit', () async {
      expect(source.status, SourceStatus.idle);
      await source.start();
      expect(source.status.phase, SourcePhase.connected);
      expect(source.providesCoordinates, isTrue);
    });

    test('throwAt meldet exaktes Feld und Position', () async {
      final dart = source.throwAt(const BoardPoint(0, 0.61));
      await pumpEventQueue();
      expect(dart.segment, Segment.triple(20));
      expect(dart.position, const BoardPoint(0, 0.61));
      expect(dart.source, DartSourceKind.simulator);
      expect((events.single as DartThrown).index, 0);
    });

    test('nach drei Darts automatischer Takeout', () async {
      for (var i = 0; i < 3; i++) {
        source.throwAt(BoardGeometry.centerOf(Segment.single(20)));
      }
      await pumpEventQueue();
      expect(events.map((e) => e.runtimeType), [DartThrown, DartThrown, DartThrown, TakeoutStarted, TakeoutFinished]);
      expect(source.currentVisit, isEmpty);
    });

    test('Takeout mit Verzögerung', () async {
      source.takeoutDelay = const Duration(milliseconds: 20);
      for (var i = 0; i < 3; i++) {
        source.throwAt(BoardPoint.center);
      }
      await pumpEventQueue();
      expect(events.last, isA<TakeoutStarted>());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(events.last, isA<TakeoutFinished>());
    });

    test('aimAt streut um das Ziel, ohne Streuung exakt', () {
      source.autoTakeout = false;
      expect(source.aimAt(Segment.triple(19), spread: 0).segment, Segment.triple(19));
      final hits = [for (var i = 0; i < 300; i++) source.aimAt(Segment.triple(20), spread: 0.05)];
      final onTarget = hits.where((d) => d.segment == Segment.triple(20)).length;
      final nearby = hits.where((d) => const {20, 1, 5}.contains(d.segment.number)).length;
      expect(onTarget, greaterThan(30));
      expect(onTarget, lessThan(300));
      expect(nearby, greaterThan(250));
    });

    test('undoLast entfernt den letzten Dart', () async {
      source.autoTakeout = false;
      source.throwAt(BoardPoint.center);
      expect(source.undoLast(), isTrue);
      expect(source.undoLast(), isFalse);
      await pumpEventQueue();
      expect(events.map((e) => e.runtimeType), [DartThrown, DartUndone]);
    });

    test('vierter Dart ohne Takeout beginnt neue Aufnahme', () async {
      source.autoTakeout = false;
      for (var i = 0; i < 4; i++) {
        source.throwAt(BoardPoint.center);
      }
      await pumpEventQueue();
      expect(events.whereType<TakeoutFinished>(), hasLength(1));
      expect(source.currentVisit, hasLength(1));
    });
  });

  group('ManualSource', () {
    test('Eingabe ohne Koordinaten, Weiter füllt mit Miss auf', () async {
      final source = ManualSource();
      final events = <DartEvent>[];
      final sub = source.events.listen(events.add);
      expect(source.providesCoordinates, isFalse);

      final d = source.enter(Segment.double(16));
      expect(d.position, isNull);
      expect(d.source, DartSourceKind.manual);
      source.nextVisit(fillWithMisses: true);
      await pumpEventQueue();

      final thrown = events.whereType<DartThrown>().map((e) => e.dart.segment).toList();
      expect(thrown, [Segment.double(16), Segment.miss, Segment.miss]);
      expect(events.last, isA<TakeoutFinished>());

      source.enter(Segment.bull);
      source.resetVisit();
      await pumpEventQueue();
      expect(events.last, isA<TurnReset>());
      expect(source.currentVisit, isEmpty);

      await sub.cancel();
      await source.dispose();
    });
  });
}
