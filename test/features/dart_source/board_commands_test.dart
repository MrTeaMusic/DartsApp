import 'dart:io';
import 'dart:math' as math;

import 'package:dartlab/features/dart_source/data/autodarts_local_source.dart';
import 'package:dartlab/features/dart_source/domain/board_control.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_board_manager.dart';

AutodartsLocalSource sourceFor(FakeBoardManager board) =>
    AutodartsLocalSource(host: '127.0.0.1', port: board.port, random: math.Random(1));

void main() {
  late FakeBoardManager board;
  late AutodartsLocalSource source;

  setUp(() async {
    board = await FakeBoardManager.start();
    source = sourceFor(board);
  });

  tearDown(() async {
    await source.dispose();
    await board.close();
  });

  group('Pfade und Methoden', () {
    test('jeder Befehl nutzt Methode und Pfad der Home-Assistant-Integration', () {
      expect({for (final c in AutodartsCommand.values) c.name: '${c.method} ${c.path}'}, {
        'start': 'PUT /api/start',
        'stop': 'PUT /api/stop',
        'reset': 'POST /api/reset',
        'restart': 'POST /api/restart',
        'calibrate': 'POST /api/config/calibration/auto',
      });
    });

    test('Neu kalibrieren: POST auf den Kalibrier-Pfad, kein Abruf von /api/config', () async {
      board.commandStatus['POST /api/config/calibration/auto'] = 200;
      final r = await source.run(BoardAction.recalibrate, userInitiated: true);
      expect(r.ok, isTrue);
      expect(r.statusCode, 200);
      expect(board.requests, ['POST /api/config/calibration/auto']);
      expect(board.requests.where((r) => r.startsWith('GET')), isEmpty);
    });

    test('Stoppen und Starten: PUT, merkt sich den Zustand', () async {
      board.commandStatus['PUT /api/stop'] = 200;
      board.commandStatus['PUT /api/start'] = 204;
      final seen = <bool?>[];
      source.boardRunningChanges.listen(seen.add);
      expect(source.boardRunning, isNull);

      expect((await source.run(BoardAction.stop, userInitiated: true)).ok, isTrue);
      expect(source.boardRunning, isFalse);
      expect((await source.run(BoardAction.start, userInitiated: true)).statusCode, 204);
      expect(source.boardRunning, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [false, true]);
      expect(board.requests, ['PUT /api/stop', 'PUT /api/start']);
    });

    test('abgelehnter Stopp ändert den Zustand nicht', () async {
      board.commandStatus['PUT /api/stop'] = 500;
      final r = await source.run(BoardAction.stop, userInitiated: true);
      expect(r.ok, isFalse);
      expect(r.statusCode, 500);
      expect(source.boardRunning, isNull);
    });

    test('das Feld running im Board-Zustand wird übernommen', () async {
      final up = source.boardRunningChanges.firstWhere((v) => v == false);
      await source.start();
      while (board.sockets.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      board.push({'connected': true, 'running': false, 'status': 'Stopped'});
      expect(await up.timeout(const Duration(seconds: 5)), isFalse);
      expect(source.boardRunning, isFalse);
    });
  });

  group('Refresh: erst restart, bei 404/405 reset', () {
    test('restart angenommen: kein Reset', () async {
      board.commandStatus['POST /api/restart'] = 200;
      final r = await source.run(BoardAction.refresh, userInitiated: true);
      expect(r.ok, isTrue);
      expect(r.path, '/api/restart');
      expect(r.fellBackFrom, isNull);
      expect(board.requests, ['POST /api/restart']);
    });

    for (final unknown in [404, 405]) {
      test('restart mit $unknown: Rückfall auf reset', () async {
        board.commandStatus['POST /api/restart'] = unknown;
        board.commandStatus['POST /api/reset'] = 200;
        final r = await source.run(BoardAction.refresh, userInitiated: true);
        expect(board.requests, ['POST /api/restart', 'POST /api/reset']);
        expect(r.ok, isTrue);
        expect(r.path, '/api/reset');
        expect(r.fellBackFrom, '/api/restart');
        expect(r.fallbackStatusCode, unknown);
      });
    }

    test('auch der Reset schlägt fehl: Status des Resets, Rückfall vermerkt', () async {
      board.commandStatus['POST /api/reset'] = 500;
      final r = await source.run(BoardAction.refresh, userInitiated: true);
      expect(board.requests, ['POST /api/restart', 'POST /api/reset']);
      expect(r.ok, isFalse);
      expect(r.statusCode, 500);
      expect(r.fallbackStatusCode, 404);
    });

    test('anderer Fehler beim Restart (500): kein Rückfall', () async {
      board.commandStatus['POST /api/restart'] = 500;
      final r = await source.run(BoardAction.refresh, userInitiated: true);
      expect(board.requests, ['POST /api/restart']);
      expect(r.statusCode, 500);
      expect(r.fellBackFrom, isNull);
    });

    test('Board nicht erreichbar: Fehlertext, kein Rückfall', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final lost = AutodartsLocalSource(host: '127.0.0.1', port: port, connectTimeout: const Duration(seconds: 2));
      final raw = <RawMessage>[];
      lost.rawMessages.listen(raw.add);
      final r = await lost.run(BoardAction.refresh, userInitiated: true);
      expect(r.answered, isFalse);
      expect(r.ok, isFalse);
      expect(r.error, isNotEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(raw.where((m) => m.channel == 'http POST /api/restart'), hasLength(1));
      expect(raw.where((m) => m.channel.contains('/api/reset')), isEmpty);
      await lost.dispose();
    });
  });

  group('Nur mithören', () {
    test('automatische Aufrufer bleiben gesperrt, auch bei jedem Befehl', () async {
      final release = source.holdListenOnly();
      expect(source.listenOnly, isTrue);
      for (final c in AutodartsCommand.values) {
        expect(await source.send(c), isFalse, reason: c.name);
        expect((await source.sendCommand(c)).blocked, isTrue, reason: c.name);
      }
      for (final a in BoardAction.values) {
        expect((await source.run(a)).blocked, isTrue, reason: a.name);
      }
      expect(board.requests, isEmpty);
      release();
    });

    test('userInitiated umgeht die Sperre, nur für diesen Aufruf', () async {
      final release = source.holdListenOnly();
      board.commandStatus['POST /api/config/calibration/auto'] = 200;
      final r = await source.run(BoardAction.recalibrate, userInitiated: true);
      expect(r.ok, isTrue);
      expect(r.blocked, isFalse);
      expect(board.requests, ['POST /api/config/calibration/auto']);
      // Die Sperre gilt danach unverändert.
      expect(source.listenOnly, isTrue);
      expect((await source.run(BoardAction.recalibrate)).blocked, isTrue);
      expect(board.requests, hasLength(1));
      release();
    });

    test('send mit userInitiated: wie sendCommand', () async {
      source.holdListenOnly();
      expect(await source.send(AutodartsCommand.reset), isFalse);
      expect(await source.send(AutodartsCommand.reset, userInitiated: true), isTrue);
      expect(board.requests, ['POST /api/reset']);
    });

    test('Refresh im Mithör-Modus: automatisch nichts, per Knopf beide Schritte', () async {
      source.holdListenOnly();
      expect((await source.run(BoardAction.refresh)).blocked, isTrue);
      expect(board.requests, isEmpty);
      final r = await source.run(BoardAction.refresh, userInitiated: true);
      expect(r.fellBackFrom, '/api/restart');
      expect(board.requests, ['POST /api/restart', 'POST /api/reset']);
    });
  });

  group('Sicherheit', () {
    test('Antwort-Bodys landen weder im Log noch im Ergebnis', () async {
      board.commandBody = '{"apiKey":"geheim-123","config":{}}';
      board.commandStatus['POST /api/config/calibration/auto'] = 200;
      final raw = <RawMessage>[];
      source.rawMessages.listen(raw.add);
      final r = await source.run(BoardAction.recalibrate, userInitiated: true);
      await Future<void>.delayed(Duration.zero);
      expect(r.statusCode, 200);
      expect(raw.map((m) => '${m.channel} ${m.payload}'), contains('http 200 /api/config/calibration/auto '));
      for (final m in raw) {
        expect('${m.channel} ${m.payload}', isNot(contains('geheim')));
      }
      expect('${r.error} ${r.path}', isNot(contains('geheim')));
    });

    test('kein Befehl ruft /api/system oder /api/config ab', () async {
      for (final a in BoardAction.values) {
        await source.run(a, userInitiated: true);
      }
      for (final r in board.requests) {
        expect(r.startsWith('GET'), isFalse, reason: r);
        expect(r, isNot(contains('/api/system')));
        expect(r.split(' ').last == '/api/config', isFalse, reason: r);
      }
    });
  });

  group('Bereitschaft', () {
    const live = SourceStatus.ready;
    test('verbunden ohne Takeout: bereit', () {
      expect(boardReadiness(live), BoardReadiness.ready);
      expect(boardReadiness(const SourceStatus(SourcePhase.polling)), BoardReadiness.ready);
      expect(boardReadiness(live, running: true), BoardReadiness.ready);
    });
    test('Takeout: gelb', () {
      expect(boardReadiness(live, takeout: true), BoardReadiness.takeout);
    });
    test('Erkennung angehalten: gestoppt, auch im Takeout', () {
      expect(boardReadiness(live, running: false), BoardReadiness.stopped);
      expect(boardReadiness(live, takeout: true, running: false), BoardReadiness.stopped);
    });
    test('getrennt: offline, ein alter Takeout zählt nicht', () {
      for (final p in [SourcePhase.reconnecting, SourcePhase.error, SourcePhase.idle]) {
        expect(boardReadiness(SourceStatus(p), takeout: true), BoardReadiness.offline, reason: p.name);
        expect(boardReadiness(SourceStatus(p)), BoardReadiness.offline, reason: p.name);
      }
    });
    test('Verbindung wird aufgebaut: connecting', () {
      expect(boardReadiness(const SourceStatus(SourcePhase.connecting), takeout: true), BoardReadiness.connecting);
    });
  });
}
