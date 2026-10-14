// Spielt Challenges mit Computergegnern ([DartBot]) durch, um die
// Sterne-Schwellen zu prüfen (siehe docs/ziele-und-challenges.md).
//
// Der Bot zielt wie ein vernünftiger Spieler: Scoren auf T20, Zahlen-Ziele
// auf das Triple (dort ist das Segment am breitesten), Doppel aufs Doppel,
// Finishes über den Checkout-Weg des Bots. Doppel-Ziele und Finish-Darts wirft
// er mit der Finish-Streuung (sie folgt echten Doppelquoten), alles andere,
// auch Bull, mit der Scoring-Streuung.
import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/challenges/domain/challenge.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';
import 'package:dartlab/features/games/domain/games/around_the_clock.dart';
import 'package:dartlab/features/games/domain/games/bobs_27.dart';
import 'package:dartlab/features/games/domain/games/bull_drill.dart';
import 'package:dartlab/features/games/domain/games/catch_40.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_training.dart';
import 'package:dartlab/features/games/domain/games/cricket.dart';
import 'package:dartlab/features/games/domain/games/doubles_420.dart';
import 'package:dartlab/features/games/domain/games/doubles_ladder.dart';
import 'package:dartlab/features/games/domain/games/exact_score.dart';
import 'package:dartlab/features/games/domain/games/frustration.dart';
import 'package:dartlab/features/games/domain/games/golf.dart';
import 'package:dartlab/features/games/domain/games/halve_it.dart';
import 'package:dartlab/features/games/domain/games/jdc_challenge.dart';
import 'package:dartlab/features/games/domain/games/one_twenty_one.dart';
import 'package:dartlab/features/games/domain/games/own_games.dart';
import 'package:dartlab/features/games/domain/games/scoring_drills.dart';
import 'package:dartlab/features/games/domain/games/setup_shot.dart';
import 'package:dartlab/features/games/domain/games/shanghai.dart';
import 'package:dartlab/features/games/domain/games/switch_drill.dart';
import 'package:dartlab/features/games/domain/games/three_in_a_bed.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';
import 'package:dartlab/features/matches/domain/x01_match.dart';

final DateTime _t = DateTime(2026, 10, 14);

/// Ziel und ob der Dart mit der Finish-Streuung geworfen wird.
typedef Aim = ({Segment target, bool precise});

Aim _x01(int remaining, int dartsLeft, OutMode out) {
  final t = DartBot.aim(remaining, dartsLeft, out);
  return (target: t, precise: remaining <= DartBot.finishZone || t.score == remaining);
}

/// Shanghai: erst das Triple, dann was in der Aufnahme noch fehlt.
Aim _shanghai(int n, List<DartThrow> inVisit) {
  bool has(bool Function(Segment) f) => inVisit.any((d) => d.segment.number == n && f(d.segment));
  if (!has((s) => s.isTriple)) return (target: Segment.triple(n), precise: false);
  if (!has((s) => s.isDouble)) return (target: Segment.double(n), precise: true);
  if (!has((s) => s.isSingle)) return (target: Segment.single(n, inner: true), precise: false);
  return (target: Segment.triple(n), precise: false);
}

/// Irgendein Feld der Zahl [n] (bzw. Bull).
Aim _wedge(int n) => n == 25 ? (target: Segment.bull, precise: false) : (target: Segment.triple(n), precise: false);

/// Wohin ein vernünftiger Spieler den nächsten Dart wirft.
Aim aimFor(TrainingGame g) {
  final inVisit = g.visitClosed ? const <DartThrow>[] : g.visit;
  final left = g.dartsLeftInVisit;
  switch (g) {
    case AroundTheClock():
      final n = g.current;
      if (g.ring == RingRule.double) return (target: n == 25 ? Segment.bull : Segment.double(n), precise: true);
      return _wedge(n);
    case X01Solo():
      return _x01(g.remaining, left, g.outMode);
    case CheckoutTraining():
      return _x01(g.remaining, left, OutMode.fromDoubleOut(g.doubleOut));
    case Catch40():
      return _x01(g.remaining, left, OutMode.double);
    case OneTwentyOne():
      return _x01(g.remaining, left, OutMode.fromDoubleOut(g.doubleOut));
    case TargetPractice():
      return (target: Segment.triple(g.number), precise: false);
    case ScoreTarget() || HighscoreHunt():
      return (target: Segment.triple(20), precise: false);
    case BullDrill():
      return (target: Segment.bull, precise: false);
    case Shanghai():
      return g.current == 25 ? (target: Segment.bull, precise: false) : _shanghai(g.current, inVisit);
    case DartsGolf():
      return (target: Segment.double(g.hole), precise: true);
    case ThreeHitsRound():
      return _wedge(g.current);
    case CricketTraining():
      return _wedge(g.active.first);
    case SkipAroundTheWorld():
      return _wedge(g.current);
    case HalveIt():
      final r = g.current;
      return switch (r.kind) {
        RoundTargetKind.number => (target: Segment.triple(r.number), precise: false),
        RoundTargetKind.anyDouble => (target: Segment.double(20), precise: true),
        RoundTargetKind.anyTriple => (target: Segment.triple(20), precise: false),
        RoundTargetKind.bull || RoundTargetKind.bullseye => (target: Segment.bull, precise: false),
      };
    case Bobs27():
      return (target: g.currentSegment, precise: true);
    case JdcChallenge():
      if (g.part == 2) return (target: g.currentDouble, precise: true);
      return _shanghai(g.currentNumber, inVisit);
    case Doubles420():
      return (target: g.currentSegment, precise: true);
    case SwitchDrill():
      return (target: g.nextTarget, precise: false);
    case DoublesLadder():
      return (target: g.currentSegment, precise: true);
    case SetupShot():
      final s = g.suggestion?.first ?? Segment.single(20, inner: true);
      return (target: s, precise: g.rest <= DartBot.finishZone);
    case ThreeInABed():
      return _wedge(g.current);
    case Frustration():
      if (g.inDoublePhase) return (target: g.currentSegment, precise: true);
      return (target: Segment.triple(20), precise: false);
    case ExactScore():
      return _x01(g.remaining, left, OutMode.straight);
  }
  throw StateError('Kein Ziel für ${g.runtimeType}');
}

/// Darts-Golf („letzter Dart zählt“): aufhören, sobald der Wert nicht
/// schlechter ist als das, was weitere Darts im Schnitt bringen.
class GolfPlan {
  GolfPlan(DartBot bot, DartsGolf g) {
    final r = math.Random(99);
    final probe = DartBot(sigma: bot.sigma, finishSigma: bot.finishSigma, random: r);
    for (var hole = 1; hole <= 20; hole++) {
      final values = [
        for (var i = 0; i < 3000; i++) g.strokesFor(probe.throwAt(Segment.double(hole), sigma: bot.finishSigma).segment, hole),
      ];
      final c1 = values.reduce((a, b) => a + b) / values.length;
      final c2 = values.map((v) => math.min(v.toDouble(), c1)).reduce((a, b) => a + b) / values.length;
      _cont[hole] = [double.negativeInfinity, c1, c2];
    }
  }
  final Map<int, List<double>> _cont = {};

  /// Soll nach diesem Dart aufgehört werden?
  bool stop(DartsGolf g) {
    if (g.visitClosed || g.visit.isEmpty) return false;
    final v = g.currentHoleValue!;
    final left = 3 - g.visit.length;
    if (left <= 0) return false;
    return v <= _cont[g.hole]![left];
  }
}

/// Spielt eine Trainings-Challenge mit [bot] bis zum Ende; Kennzahlen des
/// Spiels.
Map<String, num> playChallenge(Challenge c, DartBot bot, int seed) {
  final g = c.definition!.start(c.config, seed)..prepare();
  final golf = g is DartsGolf ? GolfPlan(bot, g) : null;
  var guard = 0;
  while (!g.finished && guard++ < 20000) {
    if (g.visitClosed) {
      g.endVisit();
    } else if (golf != null && golf.stop(g as DartsGolf)) {
      g.endVisit();
      continue;
    }
    final a = aimFor(g);
    g.throwDart(bot.throwAt(a.target, at: _t, sigma: a.precise ? bot.finishSigma : null));
  }
  return g.result.metrics;
}

/// Match gegen den Computer: Spieler [me] (Index 0, beginnt) gegen [cpu];
/// die Kennzahlen, nach denen [Challenge.starsFor] wertet.
Map<String, num> playMatch(Challenge c, DartBot me, DartBot cpu) {
  final m = X01Match(format: c.match!.format, playerCount: 2);
  var guard = 0;
  while (!m.finished && guard++ < 20000) {
    if (m.visitClosed) {
      m.endVisit();
      continue;
    }
    m.throwDart((m.current == 0 ? me : cpu).next(m, at: _t));
  }
  final p = m.players[0];
  return {
    'won': m.winner == 0 ? 1 : 0,
    'legsLost': m.legs.length - p.totalLegs,
    'average': p.average ?? 0,
  };
}
