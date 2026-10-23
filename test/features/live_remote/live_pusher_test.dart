import 'dart:async';

import 'package:dartlab/features/live_remote/data/live_pusher.dart';
import 'package:dartlab/features/live_remote/data/live_sink.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/sync/data/cloud_api.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_states.dart';

class FakeSink implements LiveSink {
  final sent = <ScreenState>[];
  int checks = 0;
  bool closed = false;

  /// Wird bei der nächsten Prüfung bzw. beim nächsten Senden geworfen (einmal).
  Object? failCheck;
  Object? failSend;

  /// Hält das Senden an, bis es fertig ist.
  Completer<void>? gate;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<void> check() async {
    checks++;
    final e = failCheck;
    if (e != null) {
      failCheck = null;
      throw e;
    }
  }

  @override
  Future<void> send(ScreenState state) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final g = gate;
      if (g != null) await g.future;
      final e = failSend;
      if (e != null) {
        failSend = null;
        throw e;
      }
      sent.add(state);
    } finally {
      inFlight--;
    }
  }

  @override
  void close() => closed = true;

  List<String> get kinds => [for (final s in sent) s.isIdle ? 'idle' : '${s.title}/${s.hitSerial}'];
}

/// Ein steuerbarer Stand und ein Pusher mit den Standardzeiten.
class Rig {
  Rig({this.sink2}) {
    sink = sink2 ?? FakeSink();
    pusher = LivePusher(
      snapshot: () {
        if (throwing) throw StateError('kaputt');
        return state;
      },
      sink: sink,
      onStatus: statuses.add,
    );
  }

  final FakeSink? sink2;
  late final FakeSink sink;
  late final LivePusher pusher;
  ScreenState state = ScreenState.idle;
  bool throwing = false;
  final statuses = <LivePushInfo>[];

  List<LivePushStatus> get kinds => [for (final s in statuses) s.status];
}

Future<void> after(WidgetTester tester, Duration d) => tester.pump(d);
Duration ms(int v) => Duration(milliseconds: v);
Duration s(int v) => Duration(seconds: v);

void main() {
  group('Ohne Spiel', () {
    testWidgets('prüft den Cloud-Speicher einmal und sendet sonst nichts', (tester) async {
      final r = Rig()..pusher.start();
      await after(tester, ms(10));
      expect(r.sink.checks, 1);
      expect(r.kinds, [LivePushStatus.waiting]);
      // Eine Minute Leerlauf: der Stand wird lokal geprüft, aber nie gesendet.
      for (var i = 0; i < 12; i++) {
        await after(tester, s(5));
      }
      expect(r.sink.sent, isEmpty);
      expect(r.sink.checks, 1, reason: 'keine weitere Anfrage ohne Spiel');
      r.pusher.stop();
      expect(r.sink.closed, isTrue);
    });

    testWidgets('kein "idle", wenn nie etwas lief', (tester) async {
      final r = Rig()..pusher.start();
      r.pusher.markDirty();
      await after(tester, s(10));
      r.pusher.markDirty();
      await after(tester, s(10));
      expect(r.sink.sent, isEmpty);
      r.pusher.stop(sendIdle: true);
      await after(tester, ms(10));
      expect(r.sink.sent, isEmpty);
    });

    testWidgets('vor start() und nach stop() tut markDirty nichts', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.markDirty();
      await after(tester, s(5));
      expect(r.sink.checks, 0);
      expect(r.sink.sent, isEmpty);
      r.pusher.start();
      await after(tester, ms(10));
      expect(r.sink.sent, hasLength(1));
      r.pusher.stop();
      r.pusher.markDirty();
      await after(tester, s(60));
      expect(r.sink.sent, hasLength(1));
    });
  });

  group('Drosselung', () {
    testWidgets('der erste Stand geht sofort, Änderungen dazwischen werden gesammelt', (tester) async {
      final r = Rig()..pusher.start();
      await after(tester, ms(10));
      r.state = liveMatch;
      r.pusher.markDirty();
      await after(tester, ms(10));
      expect(r.sink.kinds, ['501 · X01-Match/40']);

      // Viele Änderungen innerhalb von 1,5 s: erst nach Ablauf geht der letzte Stand raus.
      for (var i = 1; i <= 20; i++) {
        r.state = ScreenState(kind: ScreenKind.match, title: 'Match', hitSerial: 100 + i);
        r.pusher.markDirty();
        await after(tester, ms(50));
      }
      expect(r.sink.sent, hasLength(1), reason: 'noch in der Pause');
      await after(tester, ms(600));
      expect(r.sink.kinds, ['501 · X01-Match/40', 'Match/120']);
      expect(r.sink.maxInFlight, 1);
      r.pusher.stop();
    });

    testWidgets('höchstens ein Paket je 1,5 s, auch bei Dauerfeuer', (tester) async {
      final r = Rig()..pusher.start();
      await after(tester, ms(10));
      var serial = 0;
      // 30 Sekunden lang alle 100 ms eine Änderung.
      for (var i = 0; i < 300; i++) {
        r.state = ScreenState(kind: ScreenKind.live, title: 'Live', hitSerial: ++serial);
        r.pusher.markDirty();
        await after(tester, ms(100));
      }
      expect(r.sink.sent.length, lessThanOrEqualTo(21), reason: '30 s / 1,5 s = 20, dazu das erste');
      expect(r.sink.sent.length, greaterThanOrEqualTo(18));
      expect(r.sink.sent.last.hitSerial, greaterThan(serial - 20), reason: 'zuletzt der neueste Stand');
      r.pusher.stop();
    });

    testWidgets('unveränderter Stand wird nicht noch einmal gesendet', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      for (var i = 0; i < 10; i++) {
        r.pusher.markDirty();
        await after(tester, ms(300));
      }
      expect(r.sink.sent, hasLength(1));
      r.pusher.stop();
    });

    testWidgets('zwei gleiche Stände nacheinander: ein Paket', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      r.state = liveMatchNext;
      r.pusher.markDirty();
      await after(tester, s(2));
      // Gleicher Inhalt, neues Objekt.
      r.state = ScreenState.fromJson(liveMatchNext.toJson());
      r.pusher.markDirty();
      await after(tester, s(2));
      expect(r.sink.sent, hasLength(2));
      r.pusher.stop();
    });

    testWidgets('ein langsames Senden wird nicht überholt', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.gate = Completer<void>();
      r.pusher.start();
      await after(tester, ms(10));
      r.state = liveMatchNext;
      for (var i = 0; i < 5; i++) {
        r.pusher.markDirty();
        await after(tester, s(1));
      }
      expect(r.sink.inFlight, 1);
      expect(r.sink.sent, isEmpty);
      r.sink.gate!.complete();
      r.sink.gate = null;
      await after(tester, ms(10));
      await after(tester, s(2));
      expect(r.sink.maxInFlight, 1);
      expect(r.sink.kinds, ['501 · X01-Match/40', '501 · X01-Match/41']);
      r.pusher.stop();
    });
  });

  group('Herzschlag', () {
    testWidgets('läuft ein Spiel ohne Änderung, geht alle 20 s ein Paket raus', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      expect(r.sink.sent, hasLength(1));
      await after(tester, s(19));
      expect(r.sink.sent, hasLength(1));
      await after(tester, s(2));
      expect(r.sink.sent, hasLength(2), reason: 'nach ~20 s');
      await after(tester, s(20));
      expect(r.sink.sent, hasLength(3));
      await after(tester, s(60));
      expect(r.sink.sent, hasLength(6));
      // Gleicher Inhalt, nur der Herzschlag.
      expect({for (final x in r.sink.sent) x.hitSerial}, {40});
      r.pusher.stop();
    });

    testWidgets('eine Änderung setzt den Herzschlag zurück', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, s(15));
      r.state = liveMatchNext;
      r.pusher.markDirty();
      await after(tester, s(2));
      expect(r.sink.sent, hasLength(2));
      await after(tester, s(17));
      expect(r.sink.sent, hasLength(2), reason: '20 s nach dem letzten Paket, nicht nach dem ersten');
      await after(tester, s(3));
      expect(r.sink.sent, hasLength(3));
      r.pusher.stop();
    });

    testWidgets('3 Stunden Dauerbetrieb ohne Änderung: rund 540 Herzschläge', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      for (var i = 0; i < 3 * 60 * 12; i++) {
        await after(tester, s(5));
      }
      expect(r.sink.sent.length, inInclusiveRange(540, 545));
      r.pusher.stop();
    });
  });

  group('Spielende', () {
    testWidgets('am Ende geht genau einmal ein idle-Stand raus, danach Ruhe', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      r.state = ScreenState.idle;
      r.pusher.markDirty();
      await after(tester, s(2));
      expect(r.sink.kinds, ['501 · X01-Match/40', 'idle']);
      // Kein Herzschlag mehr, keine weiteren Pakete.
      for (var i = 0; i < 24; i++) {
        r.pusher.markDirty();
        await after(tester, s(5));
      }
      expect(r.sink.sent, hasLength(2));
      r.pusher.stop();
    });

    testWidgets('mehrere Spiele nacheinander: je Ende ein idle', (tester) async {
      final r = Rig()..state = liveSolo;
      r.pusher.start();
      await after(tester, ms(10));
      r.state = ScreenState.idle;
      r.pusher.markDirty();
      await after(tester, s(2));
      r.state = liveMatch;
      r.pusher.markDirty();
      await after(tester, s(2));
      r.state = ScreenState.idle;
      r.pusher.markDirty();
      await after(tester, s(2));
      expect(r.sink.kinds, ['X01-Solo/18', 'idle', '501 · X01-Match/40', 'idle']);
      r.pusher.stop();
    });

    testWidgets('stop(sendIdle) während eines Spiels schickt noch ein idle und schließt', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      r.pusher.stop(sendIdle: true);
      await after(tester, ms(10));
      expect(r.sink.kinds, ['501 · X01-Match/40', 'idle']);
      expect(r.sink.closed, isTrue);
      // Danach rührt sich nichts mehr.
      await after(tester, s(120));
      expect(r.sink.sent, hasLength(2));
    });

    testWidgets('stop(sendIdle) nach dem Spielende sendet nichts mehr', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      r.state = ScreenState.idle;
      r.pusher.markDirty();
      await after(tester, s(2));
      r.pusher.stop(sendIdle: true);
      await after(tester, ms(10));
      expect(r.sink.sent, hasLength(2));
    });

    testWidgets('das idle beim Beenden scheitert still', (tester) async {
      final r = Rig()..state = liveMatch;
      r.pusher.start();
      await after(tester, ms(10));
      r.sink.failSend = const SyncException(SyncFailure.unreachable);
      r.pusher.stop(sendIdle: true);
      await after(tester, ms(10));
      expect(r.sink.closed, isTrue);
    });
  });

  group('Fehler stören das Spiel nie', () {
    testWidgets('kein Netz: still wiederholen mit wachsendem Abstand, danach weiter', (tester) async {
      final r = Rig()..state = liveMatch;
      var failures = 0;
      final failing = _FlakySink(fails: 6, error: () => const SyncException(SyncFailure.unreachable), onFail: () => failures++);
      final pusher = LivePusher(snapshot: () => r.state, sink: failing, onStatus: r.statuses.add)..start();
      await tester.pump(ms(10));
      expect(failures, 1);
      expect(r.kinds.last, LivePushStatus.unreachable);
      // 3 s, 6 s, 12 s, 30 s, 60 s: Versuche nach dem Abstand.
      final expected = [3, 6, 12, 30, 60];
      var total = 0;
      for (var i = 0; i < expected.length; i++) {
        await tester.pump(s(expected[i]) - ms(500));
        expect(failures, i + 1, reason: 'vor Ablauf von ${expected[i]} s noch kein neuer Versuch');
        await tester.pump(ms(600));
        expect(failures, i + 2, reason: 'nach ${expected[i]} s');
        total += expected[i];
      }
      expect(total, 111);
      // Der siebte Versuch klappt; der Abstand bleibt bei 60 s gedeckelt.
      await tester.pump(s(61));
      expect(failing.sent, isNotEmpty);
      expect(r.kinds.last, LivePushStatus.ok);
      pusher.stop();
    });

    testWidgets('der Stand beim Wiederholen ist der aktuelle, nicht der alte', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.failSend = const SyncException(SyncFailure.unreachable);
      r.pusher.start();
      await after(tester, ms(10));
      expect(r.sink.sent, isEmpty);
      r.state = liveMatchNext;
      r.pusher.markDirty();
      await after(tester, s(4));
      expect(r.sink.kinds, ['501 · X01-Match/41']);
      expect(r.kinds.last, LivePushStatus.ok);
      r.pusher.stop();
    });

    testWidgets('Fehlerarten werden gemeldet: Server, Zugang', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.failSend = const SyncException(SyncFailure.server, 'HTTP 429');
      r.pusher.start();
      await after(tester, ms(10));
      expect(r.statuses.last.status, LivePushStatus.server);
      expect(r.statuses.last.detail, 'HTTP 429');
      r.sink.failSend = const SyncException(SyncFailure.wrongKey);
      await after(tester, s(4));
      expect(r.statuses.last.status, LivePushStatus.wrongKey);
      await after(tester, s(61));
      expect(r.statuses.last.status, LivePushStatus.ok);
      r.sink.failSend = StateError('irgendwas');
      r.state = liveMatchNext;
      r.pusher.markDirty();
      await after(tester, s(2));
      expect(r.statuses.last.status, LivePushStatus.server);
      r.pusher.stop();
    });

    testWidgets('ein unerwarteter Fehler im Sink wirft nie aus dem Pusher heraus', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.failCheck = StateError('Prüfung kaputt');
      r.pusher.start();
      await after(tester, ms(10));
      expect(tester.takeException(), isNull);
      expect(r.statuses.last.status, LivePushStatus.server);
      await after(tester, s(4));
      expect(r.sink.sent, hasLength(1));
      r.pusher.stop();
    });

    testWidgets('ein Fehler beim Zusammenstellen des Stands wird übergangen', (tester) async {
      final r = Rig()..state = liveMatch;
      r.throwing = true;
      r.pusher.start();
      await after(tester, ms(10));
      expect(tester.takeException(), isNull);
      expect(r.sink.sent, isEmpty);
      r.throwing = false;
      r.pusher.markDirty();
      await after(tester, s(6));
      expect(r.sink.sent, hasLength(1));
      r.pusher.stop();
    });
  });

  group('Alter Worker', () {
    testWidgets('meldet den Hinweis, sendet nichts und prüft nur selten neu', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.failCheck = const CloudTooOldException();
      r.pusher.start();
      await after(tester, ms(10));
      expect(r.kinds, [LivePushStatus.workerTooOld]);
      expect(r.sink.sent, isEmpty);
      expect(r.sink.checks, 1);
      // Mitten im Spiel: trotzdem nur alle 5 Minuten eine Anfrage.
      for (var i = 0; i < 4; i++) {
        r.state = ScreenState(kind: ScreenKind.match, title: 'M', hitSerial: i);
        r.pusher.markDirty();
        await after(tester, s(60));
      }
      expect(r.sink.checks, 1);
      expect(r.sink.sent, isEmpty);
      await after(tester, s(61));
      // Fünf Minuten sind um: Der Worker ist inzwischen aktualisiert.
      expect(r.sink.checks, 2);
      expect(r.sink.sent, hasLength(1));
      expect(r.kinds.last, LivePushStatus.ok);
      r.pusher.stop();
    });

    testWidgets('ein Worker, der erst beim Senden 404 meldet, wird genauso behandelt', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.failSend = const CloudTooOldException();
      r.pusher.start();
      await after(tester, ms(10));
      expect(r.statuses.last.status, LivePushStatus.workerTooOld);
      r.pusher.stop();
    });
  });

  group('Statusmeldungen', () {
    testWidgets('waiting, dann ok mit Zeit des letzten Pakets', (tester) async {
      final r = Rig()..pusher.start();
      await after(tester, ms(10));
      expect(r.statuses.last.status, LivePushStatus.waiting);
      expect(r.statuses.last.lastSent, isNull);
      r.state = liveMatch;
      r.pusher.markDirty();
      await after(tester, ms(10));
      expect(r.statuses.last.status, LivePushStatus.ok);
      expect(r.statuses.last.lastSent, isNotNull);
      r.pusher.stop();
    });

    testWidgets('nach dem Stopp kommen keine Meldungen mehr', (tester) async {
      final r = Rig()..state = liveMatch;
      r.sink.gate = Completer<void>();
      r.pusher.start();
      await after(tester, ms(10));
      final count = r.statuses.length;
      r.pusher.stop();
      r.sink.gate!.complete();
      await after(tester, s(5));
      expect(r.statuses.length, count);
      expect(r.sink.sent, hasLength(1), reason: 'das laufende Senden endet, meldet aber nichts mehr');
    });
  });
}

/// Scheitert [fails] Mal, dann klappt es.
class _FlakySink extends FakeSink {
  _FlakySink({required this.fails, required this.error, required this.onFail});
  int fails;
  final Object Function() error;
  final void Function() onFail;

  @override
  Future<void> send(ScreenState state) async {
    if (fails > 0) {
      fails--;
      onFail();
      throw error();
    }
    await super.send(state);
  }
}
