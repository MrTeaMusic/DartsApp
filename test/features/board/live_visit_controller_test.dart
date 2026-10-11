import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/board/presentation/live_visit_controller.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DartThrow dart(Segment s, {BoardPoint? p}) =>
    DartThrow(segment: s, position: p, timestamp: DateTime(2026), source: DartSourceKind.simulator);

void main() {
  late ProviderContainer container;
  late LiveVisitController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(sp)]);
    controller = container.read(liveVisitProvider.notifier);
  });
  tearDown(() => container.dispose());

  LiveVisitState state() => container.read(liveVisitProvider);

  test('Aufnahme sammelt Darts und summiert Punkte', () {
    controller.apply(DartThrown(dart(Segment.triple(20))));
    controller.apply(DartThrown(dart(Segment.triple(20))));
    controller.apply(DartThrown(dart(Segment.single(20))));
    expect(state().visitScore, 140);
    expect(state().visit, hasLength(3));
    expect(state().history, hasLength(3));
  });

  test('Takeout leert die Aufnahme, Historie bleibt', () {
    controller.apply(DartThrown(dart(Segment.bull)));
    controller.apply(TakeoutStarted(DateTime(2026)));
    expect(state().takeoutInProgress, isTrue);
    controller.apply(TakeoutFinished(DateTime(2026)));
    expect(state().visit, isEmpty);
    expect(state().takeoutInProgress, isFalse);
    expect(state().history.single.segment, Segment.bull);
  });

  test('Korrektur und Rücknahme wirken auf Aufnahme und Historie', () {
    controller.apply(DartThrown(dart(Segment.single(1))));
    controller.apply(DartThrown(dart(Segment.single(5))));
    controller.apply(DartCorrected(0, dart(Segment.double(1))));
    expect(state().visit.first.segment, Segment.double(1));
    expect(state().history.first.segment, Segment.double(1));
    controller.apply(DartUndone(DateTime(2026)));
    expect(state().visit.map((d) => d.segment), [Segment.double(1)]);
    expect(state().history, hasLength(1));
    // Ungültige Korrektur/Rücknahme wird ignoriert.
    controller.apply(DartCorrected(5, dart(Segment.miss)));
    controller.apply(TurnReset(DateTime(2026)));
    controller.apply(DartUndone(DateTime(2026)));
    expect(state().visit, isEmpty);
  });

  test('vierter Dart ohne Takeout beginnt neue Aufnahme', () {
    for (var i = 0; i < 4; i++) {
      controller.apply(DartThrown(dart(Segment.single(i + 1))));
    }
    expect(state().visit.map((d) => d.segment), [Segment.single(4)]);
  });
}
