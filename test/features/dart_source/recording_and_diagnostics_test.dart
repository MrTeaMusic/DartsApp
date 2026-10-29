import 'dart:io';

import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/dart_source/data/autodarts_diagnostics.dart';
import 'package:dartlab/features/dart_source/data/autodarts_state_mapper.dart';
import 'package:dartlab/features/dart_source/data/recording_analysis.dart';
import 'package:dartlab/features/dart_source/domain/coordinate_calibration.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_board_manager.dart';
import '../../helpers/recordings.dart';

String fixture(String name) => File('test/fixtures/autodarts/$name').readAsStringSync();

void main() {
  group('Kalibrierung', () {
    test('Kodieren und Lesen', () {
      const c = CoordinateCalibration(swapAxes: true, mirrorY: true, scale: 0.0059);
      expect(CoordinateCalibration.decode(c.encode()), c);
      expect(CoordinateCalibration.decode(null), CoordinateCalibration.identity);
      expect(CoordinateCalibration.decode('kaputt'), CoordinateCalibration.identity);
      expect(CoordinateCalibration.identity.encode(), ';1.0000');
    });

    test('Mapper wendet die Kalibrierung auf die Koordinaten an', () {
      final m = AutodartsStateMapper(calibration: const CoordinateCalibration(mirrorY: true, scale: 0.5));
      m.update({'numThrows': 0, 'throws': <Object>[]});
      final e = m.update({
        'numThrows': 1,
        'throws': [
          {'segment': {'number': 3, 'multiplier': 2}, 'coords': {'x': 0.2, 'y': 1.0}},
        ],
      }).single as DartThrown;
      expect(e.dart.position, const BoardPoint(0.1, -0.5));
    });
  });

  group('Mitschnitt-Prüfung', () {
    test('synthetischer Mitschnitt im Debug-Format', () {
      final a = RecordingAnalysis.analyze(fixture('synthetisch-community-format.jsonl'));
      expect(a.darts.map((d) => d.segment.name), ['T20', 'D6', 'D3', 'BULL', '25', 'T19', 'MISS']);
      expect(a.corrections, 1);
      expect(a.takeouts, 2);
      expect(a.warnings, isEmpty);
      expect(a.sawThrowsField, isTrue);
      expect(a.messageTypes, {'state': 12, 'motion_state': 1});
      expect(a.agreement(CoordinateCalibration.identity), 1.0);
      expect(a.suggestCalibration(), CoordinateCalibration.identity);
    });

    test('erkennt gespiegelte y-Achse', () {
      final a = RecordingAnalysis.analyze(recording(sample, (p) => BoardPoint(p.x, -p.y)));
      expect(a.agreement(CoordinateCalibration.identity), lessThan(0.5));
      final c = a.suggestCalibration()!;
      expect(c, const CoordinateCalibration(mirrorY: true));
      expect(a.agreement(c), 1.0);
    });

    test('erkennt vertauschte Achsen und Maßstab in Millimetern', () {
      final a = RecordingAnalysis.analyze(recording(sample, (p) => BoardPoint(p.y * 170, p.x * 170)));
      final c = a.suggestCalibration()!;
      expect(c.swapAxes, isTrue);
      expect(c.scale, closeTo(1 / 170, 0.0002));
      expect(a.agreement(c), greaterThanOrEqualTo(0.9));
    });

    test('ohne throws-Feld wird das gemeldet', () {
      final a = RecordingAnalysis.analyze('{"type":"x"}\n{"numThrows":0,"running":true}\nkein json');
      expect(a.sawThrowsField, isFalse);
      expect(a.darts, isEmpty);
      expect(a.suggestCalibration(), isNull);
      expect(a.lines, 3);
    });
  });

  test('alle Mitschnitte in test/fixtures/autodarts laufen ohne Warnung durch', () {
    final files = Directory('test/fixtures/autodarts').listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final a = RecordingAnalysis.analyze(f.readAsStringSync());
      expect(a.warnings, isEmpty, reason: f.path);
      final agreement = a.agreement(CoordinateCalibration.identity);
      if (agreement != null) expect(agreement, greaterThanOrEqualTo(0.9), reason: f.path);
    }
  });

  test('echter Mitschnitt: Board Manager 2.0.2 unter Windows', () {
    final a = RecordingAnalysis.analyze(fixture('board-manager-2.0.2-windows.jsonl'));
    // Der Mitschnitt beginnt mit dem ersten Dart, der trotzdem zählen muss.
    expect(a.darts.map((d) => d.segment.name), ['T20', 'T20', 'T5', 'S12', 'MISS', 'S20']);
    expect(a.takeouts, 2);
    expect(a.corrections, 0);
    expect(a.sawThrowsField, isTrue);
    expect(a.warnings, isEmpty);
    expect(a.agreement(CoordinateCalibration.identity), 1.0);
    expect(a.suggestCalibration(), CoordinateCalibration.identity);
  });

  test('echter Mitschnitt: neueres Board-Manager-Format (flache Felder, camelCase), 29.10.2026', () {
    final a = RecordingAnalysis.analyze(fixture('board-manager-neues-format-2026-10-29.jsonl'));
    expect(a.warnings, isEmpty);
    expect(a.darts.map((d) => d.segment.name), ['S12', 'S20', 'S20', 'S5', 'T20', 'S5']);
    // Der zweite Takeout am Ende zählt, "takeoutFinished" bei steckendem S5 nicht.
    expect(a.takeouts, 2);
    expect(a.corrections, 0);
    expect(a.sawThrowsField, isTrue);
    expect(a.agreement(CoordinateCalibration.identity), 1.0);
    expect(a.suggestCalibration(), CoordinateCalibration.identity);
  });

  test('Mapper: flaches Format liefert Segment, Koordinaten und genau einen Dart je Wurf', () {
    final m = AutodartsStateMapper();
    Map<String, Object?> t(String name, int n, int mult, String bed) =>
        {'segmentName': name, 'segmentNumber': n, 'multiplier': mult, 'bed': bed, 'coordsX': 0.0, 'coordsY': 0.6};
    m.update({'event': 'takeoutFinished', 'status': 'throw', 'throws': <Object>[]});
    // Veralteter Event-Name bei schon steckendem Dart darf ihn nicht wieder löschen.
    final first = m.update({'event': 'takeoutFinished', 'status': 'throw', 'throws': [t('T20', 20, 3, 'Triple')]});
    expect(first.whereType<DartThrown>().map((e) => e.dart.segment.name), ['T20']);
    expect((first.single as DartThrown).dart.position, const BoardPoint(0.0, 0.6));
    final again = m.update({'event': 'throwDetected', 'status': 'throw', 'throws': [t('T20', 20, 3, 'Triple')]});
    expect(again, isEmpty);
    expect(m.warnings, isEmpty);
  });

  group('Verbindungstest', () {
    late FakeBoardManager board;
    tearDown(() => board.close());

    test('alles erreichbar', () async {
      board = await FakeBoardManager.start()..greet = true;
      final checks = await AutodartsDiagnostics(host: '127.0.0.1', port: board.port).run();
      expect({for (final c in checks) c.kind: c.result}, {
        CheckKind.http: CheckResult.ok,
        CheckKind.stateFormat: CheckResult.ok,
        CheckKind.throwsField: CheckResult.ok,
        CheckKind.detection: CheckResult.ok,
        CheckKind.webSocket: CheckResult.ok,
      });
      expect(checks.last.detail, 'state');
      expect(board.requests.where((r) => r.contains('system') || r.contains('config')), isEmpty);
    });

    test('ohne throws, Erkennung gestoppt, stiller WebSocket', () async {
      board = await FakeBoardManager.start(silent: true);
      board.state = {'connected': true, 'running': false, 'status': 'Stopped'};
      final checks = await AutodartsDiagnostics(host: '127.0.0.1', port: board.port, messageWait: const Duration(milliseconds: 200)).run();
      final byKind = {for (final c in checks) c.kind: c};
      expect(byKind[CheckKind.throwsField]!.reason, CheckReason.missingThrows);
      expect(byKind[CheckKind.detection]!.reason, CheckReason.stopped);
      expect(byKind[CheckKind.webSocket]!.result, CheckResult.ok);
      expect(byKind[CheckKind.webSocket]!.reason, CheckReason.quiet);
    });

    test('leeres Board wie bei Board Manager 2.0.2: throws fehlt, ist aber kein Fehler', () async {
      board = await FakeBoardManager.start(silent: true);
      board.state = {'connected': true, 'event': 'Takeout finished', 'numThrows': 0, 'running': true, 'status': 'Throw'};
      final checks = await AutodartsDiagnostics(host: '127.0.0.1', port: board.port, messageWait: const Duration(milliseconds: 200)).run();
      final throwsCheck = checks.firstWhere((c) => c.kind == CheckKind.throwsField);
      expect(throwsCheck.result, CheckResult.skipped);
      expect(throwsCheck.reason, CheckReason.boardEmpty);
      expect(checks.where((c) => c.result == CheckResult.warning || c.result == CheckResult.failed), isEmpty);
    });

    test('Anmeldung verlangt', () async {
      board = await FakeBoardManager.start(webSocket: false, stateStatus: 401);
      final checks = await AutodartsDiagnostics(host: '127.0.0.1', port: board.port).run();
      expect(checks.first.reason, CheckReason.unauthorized);
      expect(checks.where((c) => c.result == CheckResult.skipped).length, 3);
      expect(checks.last.result, CheckResult.failed);
    });

    test('niemand zu Hause', () async {
      board = await FakeBoardManager.start();
      final port = board.port;
      await board.close();
      final checks = await AutodartsDiagnostics(host: '127.0.0.1', port: port).run();
      expect(checks.first.result, CheckResult.failed);
      expect(checks.first.reason, CheckReason.refused);
      expect(checks.last.result, CheckResult.failed);
    });
  });
}
