import 'dart:math' as math;

import 'package:dartlab/features/challenges/domain/challenge.dart';
import 'package:dartlab/features/challenges/domain/challenge_catalog.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/challenge_sim.dart';

/// Anteil der Versuche mit mindestens 1, 2 und 3 Sternen für einen Bot mit
/// Average [avg] (feste Zufallsstartwerte, also reproduzierbar).
List<double> starRates(Challenge c, double avg, int runs) {
  final atLeast = [0, 0, 0];
  for (var i = 0; i < runs; i++) {
    final bot = DartBot.forAverage(avg, random: math.Random(i * 7919 + avg.round()));
    final m = c.isMatch
        ? playMatch(c, bot, DartBot.forAverage(c.match!.botAverage, random: math.Random(i * 104729 + 3)))
        : playChallenge(c, bot, i + 1);
    final stars = c.starsFor(m);
    for (var s = 0; s < stars; s++) {
      atLeast[s]++;
    }
  }
  return [for (final n in atLeast) n / runs];
}

/// Grobe Leitplanken für die Sterne-Schwellen. Die genaue Einstellung (mit
/// 1000 Versuchen je Stufe) steht in docs/ziele-und-challenges.md; dieser
/// Test fängt nur grobe Ausreißer, z. B. nach Änderungen an Spielregeln oder
/// am Bot.
void main() {
  const runs = 60;
  // Spiele, in denen ein 40er den ersten Stern bewusst selten schafft
  // (Bob's 27 überstehen, Matches gegen stärkere Gegner).
  const hardForBeginners = {'c2-7', 'c3-3'};

  for (final c in ChallengeCatalog.all) {
    test('${c.id}: Sterne passen zu Average 40, 60 und 80', () {
      final r60 = starRates(c, 60, runs);
      final r80 = starRates(c, 80, runs);
      final early = c.chapter.index <= ChallengeChapter.league.index;
      expect(r80[2], greaterThanOrEqualTo(0.15), reason: '${c.id}: 3 Sterne für einen 80er zu selten ($r80)');
      expect(r60[2], lessThanOrEqualTo(0.5), reason: '${c.id}: 3 Sterne für einen 60er zu leicht ($r60)');
      expect(r80[2], greaterThan(r60[2]), reason: c.id);
      if (early) {
        expect(r60[1], greaterThanOrEqualTo(0.4), reason: '${c.id}: 2 Sterne für einen 60er zu selten ($r60)');
        if (!hardForBeginners.contains(c.id)) {
          final r40 = starRates(c, 40, runs);
          expect(r40[0], greaterThanOrEqualTo(0.6), reason: '${c.id}: 1 Stern für einen 40er zu selten ($r40)');
        }
      }
    });
  }
}
