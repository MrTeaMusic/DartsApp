import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/history/data/history_repository.dart';
import 'package:dartlab/features/history/domain/leg_board.dart';
import 'package:dartlab/features/history/domain/session_history.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';
import '../../helpers/history_seed.dart';
import '../../helpers/leg_seed.dart';
import '../../helpers/sync_device.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device a;
  setUp(() => a = Device());
  tearDown(() => a.db.close());

  Future<SessionDetail> detail(int id) async {
    final row = (await HistoryRepository(a.db).session(id))!;
    return buildSessionDetail(row, await a.games.throwsOf(id), playerName: 'Ben');
  }

  Future<int> handMade({bool withOpponent = true}) async =>
      seedHandMadeMatch(a.games, await a.me(), DateTime(2026, 10, 1, 19), withOpponent: withOpponent);

  test('Handgebautes Match: Rest, Bust und Doppel beider Spieler je Leg', () async {
    final boards = legBoardsOf(await detail(await handMade()))!;
    expect(boards.startScore, 101);
    expect(boards.hasOpponent, isTrue);
    expect(boards.players.map((p) => p.name), ['Ben', 'Anna']);
    expect(boards.legs, hasLength(2));

    final l1 = boards.legs[0];
    expect(l1.number, 1);
    expect(l1.leg.winner, 0);
    expect(l1.sides[0].rests, [101, 20, 0], reason: 'Ben: 81, dann Checkout');
    expect(l1.sides[1].rests, [101, 41, 26], reason: 'Anna: 60, dann 3 × S5 (zählt, weil Rest 36 kein Bust ist)');
    expect(l1.sides[0].finished, isTrue);
    expect(l1.sides[1].finished, isFalse);
    expect(l1.rows, 2);

    final l2 = boards.legs[1];
    expect(l2.sides[0].rests, [101, 101, 98], reason: 'Bust lässt den Rest stehen');
    expect(l2.sides[0].visits.first.bust, isTrue);
    expect(l2.sides[1].rests, [101, 20, 0]);
    expect(l2.winnerSide!.player, 1);
  });

  test('Doppel-Versuche: Ziel, Treffer und verpasste Doppel je Aufnahme', () async {
    final boards = legBoardsOf(await detail(await handMade()))!;
    final ben1 = boards.legs[0].sides[0];
    // Rest 20: S10 ist ein Versuch auf D10 (daneben), danach Rest 10: D5 trifft.
    expect([for (final t in doubleTriesOf(ben1.visits[1])) '${t.label}:${t.hit}'], ['D10:false', 'D5:true']);
    expect([for (final t in missedDoublesOf(ben1.visits[1])) t.label], ['D10']);
    expect(doubleTriesOf(ben1.visits[0]), isEmpty, reason: 'Rest 101 ist mit einem Dart nicht zu checken');

    // Anna: bei Rest 36 daneben auf D18; der Dart bei Rest 41 und 31 zählt nicht.
    final anna1 = boards.legs[0].sides[1];
    expect([for (final t in doubleTriesOf(anna1.visits[1])) t.label], ['D18']);
    expect(missedDoublesOf(anna1.visits[1]).single.target.number, 18);

    // Aufnahmen nach Bust: die restlichen Darts zählen nicht und sind kein Versuch.
    final bust = boards.legs[1].sides[0].visits.first;
    expect(bust.darts.map((d) => d.counted), [true, true, false]);
    expect(doubleTriesOf(bust), isEmpty);
  });

  test('Doppelquote: Summen und Aufschlüsselung je Doppel, beide Spieler', () async {
    final boards = legBoardsOf(await detail(await handMade()))!;
    final ben = boards.doublesOf(0);
    expect((ben.attempts, ben.hits, ben.misses), (2, 1, 1));
    expect(ben.perDouble[10]!.attempts, 1);
    expect(ben.perDouble[10]!.hits, 0);
    expect(ben.perDouble[5]!.hits, 1);
    expect(ben.ranked.map((e) => e.key), [10, 5], reason: 'bei gleicher Zahl der Versuche das höhere Doppel zuerst');
    expect(ben.total.rate, 0.5);

    final anna = boards.doublesOf(1);
    expect((anna.attempts, anna.hits), (2, 1));
    expect(anna.perDouble.keys.toSet(), {18, 10});
    expect(boards.anyDoubles, isTrue);
    expect(doubleName(25), 'Bull');
    expect(doubleName(16), 'D16');
  });

  test('Match ohne gespeicherte Gegnerwürfe (ältere Matches): nur die eigene Seite', () async {
    final boards = legBoardsOf(await detail(await handMade(withOpponent: false)))!;
    expect(boards.hasOpponent, isFalse);
    expect(boards.players, hasLength(1));
    expect(boards.legs.every((l) => l.sides.length == 1), isTrue);
    expect(boards.legs[0].sides.single.rests, [101, 20, 0]);
    expect(boards.doublesOf(0).attempts, 2);
  });

  test('Match mit Bot: Doppelquote passt zur Checkout-Quote der Statistik', () async {
    final id = await seedMatch(a.games, await a.me(), DateTime(2026, 10, 1, 19), opponent: 'Robo', legs: 3);
    final dt = await detail(id);
    final boards = legBoardsOf(dt)!;
    expect(boards.hasOpponent, isTrue, reason: 'neue Matches speichern die Aufnahmen des Gegners');

    // Eigene Seite: genau die Kennzahlen, aus denen die Statistik die Doppel-Quote macht.
    final me = boards.doublesOf(0);
    expect(me.attempts, dt.entry.metrics['checkoutDarts']);
    expect(me.hits, dt.entry.metrics['legsWon']);
    expect(me.attempts, dt.finishAttempts);
    expect(me.hits, dt.finishHits);

    // Gegner: Versuche = gewonnene Legs / gespeicherte Checkout-Quote.
    final robo = dt.players[1].stats;
    final opp = boards.doublesOf(1);
    expect(opp.hits, robo['legs']);
    if (opp.hits > 0) expect(opp.attempts, (robo['legs']! / robo['checkoutRate']!).round());

    // Die gespeicherten Gegner-Darts sind genau die Darts, die er geworfen hat.
    final stored = [
      for (final l in dt.entry.details['legs'] as List) for (final v in (l as Map)['opp'] as List) ...(v as List),
    ];
    expect(stored.length, robo['darts']);
  });

  test('Legs enden auf dem Rest 0 des Siegers, der Rest steigt nie', () async {
    final id = await seedMatch(a.games, await a.me(), DateTime(2026, 10, 1, 19), legs: 3);
    final boards = legBoardsOf(await detail(id))!;
    for (final leg in boards.legs) {
      final winner = leg.winnerSide;
      expect(winner, isNotNull);
      expect(winner!.rests.last, 0);
      expect(winner.rests.where((r) => r == 0), hasLength(1));
      expect(leg.sides.where((s) => s != winner).every((s) => s.rests.last > 0), isTrue);
      // Der Rest sinkt nie (Bust lässt ihn stehen).
      for (final s in leg.sides) {
        for (var i = 1; i < s.rests.length; i++) {
          expect(s.rests[i], lessThanOrEqualTo(s.rests[i - 1]));
        }
      }
    }
  });

  test('X01-Training: ein Leg, eine Seite, Doppel wie in der Aufnahmenliste', () async {
    final me = await a.me();
    final sid = await a.games.startSession(playerId: me, gameId: 'x01', config: {'startScore': 101}, seed: 1);
    var seq = 0;
    for (final (v, names) in [
      ['T20', 'S1', 'S20'],
      ['S20', 'MISS', 'MISS'],
      ['S2', 'D9'],
    ].indexed) {
      for (final n in names) {
        await a.games.addThrow(sessionId: sid, playerId: me, gameId: 'x01', seq: seq++, visitIndex: v, counted: true, dart: d(n));
      }
    }
    await a.games.endSession(sid, result: const GameResult(metrics: {'average': 50}, summary: []), finished: true);
    final dt = await detail(sid);
    final boards = legBoardsOf(dt)!;
    expect(boards.hasOpponent, isFalse);
    expect(boards.legs.single.number, 0);
    expect(boards.legs.single.sides.single.rests, [101, 20, 20, 0]);
    final t = boards.doublesOf(dt.me);
    expect((t.attempts, t.hits), (dt.finishAttempts, dt.finishHits));
    expect((t.attempts, t.hits), (4, 1));
  });

  test('Kein Aufnahmenverlauf bei Spielen ohne Rest und bei Matches ohne Leg-Angaben', () async {
    final me = await a.me();
    final cricket = await seedTraining(a.games, me, 'cricket', const {}, DateTime(2026, 10, 1, 18), seed: 6);
    final atc = await seedTraining(a.games, me, 'around_the_clock', const {}, DateTime(2026, 10, 1, 19), seed: 7, stopAfter: 14);
    expect(legBoardsOf(await detail(cricket)), isNull);
    expect(legBoardsOf(await detail(atc)), isNull);
  });
}
