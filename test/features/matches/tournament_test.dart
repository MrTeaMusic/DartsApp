import 'dart:convert';
import 'dart:math' as math;

import 'package:dartlab/features/matches/domain/cpu_players.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/tournament.dart';
import 'package:flutter_test/flutter_test.dart';

Tournament create({List<int>? bestOf, List<CpuPlayer> pool = defaultCpuPlayers, int seed = 3}) => Tournament.create(
  humanName: 'Ben',
  profileId: 1,
  pool: pool,
  difficulty: 0.6,
  bestOf: bestOf ?? TournamentPreset.sprint.bestOf,
  seed: seed,
  now: DateTime(2026, 10, 11),
);

void main() {
  group('Turnier', () {
    test('16 verschiedene Teilnehmer, der Mensch genau einmal, alle in Runde 1', () {
      final t = create();
      expect(t.entrants.length, 16);
      expect(t.entrants.map((e) => e.name).toSet().length, 16);
      expect(t.entrants.where((e) => e.isHuman).single.name, 'Ben');
      expect(t.rounds.map((r) => r.length), [8, 4, 2, 1]);
      final inRound1 = [
        for (final m in t.rounds.first) ...[m.a!, m.b!],
      ]..sort();
      expect(inRound1, List.generate(16, (i) => i));
      expect(t.currentRound, 0);
      expect(t.humanMatch, isNotNull);
      expect(t.humanMatch!.round, 0);
    });

    test('Zu kurze Liste wird aufgefüllt', () {
      final t = create(pool: const [CpuPlayer('Nur Einer', 80)]);
      expect(t.entrants.length, 16);
      expect(t.entrants.any((e) => e.name == 'Nur Einer'), isTrue);
    });

    test('Stärke = Average mal Schwierigkeit, Format je Runde', () {
      final t = create(bestOf: TournamentPreset.pdc.bestOf);
      final cpu = t.entrants.indexWhere((e) => !e.isHuman);
      expect(t.botAverage(cpu), closeTo(t.entrants[cpu].average * 0.6, 1e-9));
      expect(t.formatFor(0).legsToWin, 6);
      expect(t.formatFor(3).legsToWin, 11);
      expect(t.formatFor(3).startScore, 501);
      expect(TournamentPreset.of(t.bestOf), TournamentPreset.pdc);
      expect(TournamentPreset.of([3, 5, 7, 9]), isNull);
    });

    test('Sieger rücken auf, Mensch gewinnt alles und wird Turniersieger', () {
      final t = create();
      final random = math.Random(5);
      for (var round = 0; round < Tournament.roundCount; round++) {
        final m = t.humanMatch!;
        expect(m.round, round);
        final humanIsA = m.a == t.humanIndex;
        final legs = MatchFormat.firstTo(t.bestOf[round]);
        t.record(m, winner: t.humanIndex, scoreA: humanIsA ? legs : 0, scoreB: humanIsA ? 0 : legs);
        t.simulateRound(random);
        if (round < 3) {
          expect(t.currentRound, round + 1);
          // Alle Spiele der nächsten Runde stehen fest.
          expect(t.rounds[round + 1].every((x) => x.ready), isTrue);
        }
      }
      expect(t.finished, isTrue);
      expect(t.champion, t.humanIndex);
      expect(t.humanEliminated, isFalse);
    });

    test('Nach dem Ausscheiden wird der Rest simuliert', () {
      final t = create();
      final m = t.humanMatch!;
      final other = m.a == t.humanIndex ? m.b! : m.a!;
      t.record(m, winner: other, scoreA: 1, scoreB: 2);
      expect(t.humanEliminated, isTrue);
      expect(t.humanMatch, isNull);
      final random = math.Random(9);
      while (!t.finished) {
        expect(t.simulateRound(random), greaterThan(0));
      }
      expect(t.champion, isNot(t.humanIndex));
      // Jedes Spiel hat einen gültigen Sieger mit genug Legs.
      for (final r in t.rounds) {
        for (final x in r) {
          expect(x.played, isTrue);
          final need = MatchFormat.firstTo(t.bestOf[x.round]);
          expect(x.scoreA == need || x.scoreB == need, isTrue);
          expect(x.winner, x.scoreA > x.scoreB ? x.a : x.b);
        }
      }
    });

    test('Speichern und Laden', () {
      final t = create();
      final m = t.humanMatch!;
      t.record(m, winner: t.humanIndex, scoreA: 2, scoreB: 1);
      t.simulateRound(math.Random(1));
      final back = Tournament.fromJson(jsonDecode(jsonEncode(t.toJson())))!;
      expect(back.id, t.id);
      expect(back.difficulty, 0.6);
      expect(back.entrants.map((e) => e.name), t.entrants.map((e) => e.name));
      expect(back.currentRound, 1);
      expect(back.humanMatch?.id, t.humanMatch?.id);
      expect(back.entrants[back.humanIndex].profileId, 1);
      expect(Tournament.fromJson({'entrants': []}), isNull);
    });

    test('Simuliertes Match: Sieger hat first-to Legs, der Stärkere gewinnt meistens', () {
      final random = math.Random(42);
      const format = MatchFormat(legsToWin: 3);
      var strongWins = 0;
      for (var i = 0; i < 30; i++) {
        final (a, b) = Tournament.simulateMatch(format, 95, 40, random, firstStarter: i % 2);
        expect(a == 3 || b == 3, isTrue);
        expect(a != b, isTrue);
        if (a > b) strongWins++;
      }
      expect(strongWins, greaterThan(25));
    });
  });
}
