import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/challenges/domain/challenge.dart';
import 'package:dartlab/features/challenges/domain/challenge_catalog.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spielt ein Trainingsspiel mit [pick] je Dart bis zum Ende.
/// Ohne [mustFinish] darf das Spiel offen bleiben (nicht beendete Spiele
/// bringen keine Sterne).
Map<String, num>? play(Challenge c, Segment Function(TrainingGame game) pick, {int limit = 2000, bool mustFinish = true}) {
  final game = c.definition!.start(c.config, 7)..prepare();
  var thrown = 0;
  while (!game.finished && thrown < limit) {
    if (game.visitClosed) game.endVisit();
    game.throwDart(DartThrow(segment: pick(game), timestamp: DateTime(2026, 10, 12), source: DartSourceKind.manual));
    thrown++;
  }
  if (mustFinish) expect(game.finished, isTrue, reason: '${c.id} endet nicht');
  return game.finished ? game.result.metrics : null;
}

/// Bester Dart: Wurfvorschlag, sonst das wertvollste Ziel (bei Spielen,
/// in denen das Doppel zählt, das Doppel), sonst T20.
Segment perfect(Challenge c, TrainingGame game) {
  final route = game.display.suggestion;
  if (route != null && route.isNotEmpty) return route.first;
  final targets = game.targets.toList();
  if (targets.isEmpty) return Segment.tryParse('T20')!;
  if (c.gameId == 'golf') {
    return targets.firstWhere((s) => s.multiplier == 2, orElse: () => targets.first);
  }
  targets.sort((a, b) => b.score.compareTo(a.score));
  return targets.first;
}

void main() {
  test('Katalog: 40 Challenges, 5 Kapitel mit je 8, eindeutige IDs, drei Schwellen', () {
    expect(ChallengeCatalog.all, hasLength(40));
    expect({for (final c in ChallengeCatalog.all) c.id}, hasLength(40));
    for (final ch in ChallengeChapter.values) {
      final list = ChallengeCatalog.ofChapter(ch);
      expect(list, hasLength(8), reason: ch.name);
      expect([for (final c in list) c.number], [1, 2, 3, 4, 5, 6, 7, 8]);
    }
    for (final c in ChallengeCatalog.all) {
      if (c.isMatch) {
        expect(c.thresholds, isEmpty, reason: c.id);
        continue;
      }
      expect(c.definition, isNotNull, reason: c.id);
      expect(c.thresholds, hasLength(3), reason: c.id);
      for (var i = 1; i < 3; i++) {
        final harder = c.lowerIsBetter ? c.thresholds[i] < c.thresholds[i - 1] : c.thresholds[i] > c.thresholds[i - 1];
        expect(harder, isTrue, reason: '${c.id}: Schwellen müssen schwerer werden');
      }
    }
  });

  for (final c in ChallengeCatalog.all.where((c) => !c.isMatch)) {
    test('${c.id}: perfektes Spiel bringt 3 Sterne, nur Fehlwürfe keinen', () {
      final best = play(c, (g) => perfect(c, g))!;
      expect(c.starsFor(best), 3, reason: '${c.id} ${c.scoreKey}=${best[c.scoreKey]} $best');
      final miss = play(c, (_) => Segment.miss, limit: 1000, mustFinish: false);
      if (miss != null) expect(c.starsFor(miss), 0, reason: '${c.id} ${c.scoreKey}=${miss[c.scoreKey]}');
    });
  }

  test('Match-Challenges: Sieg 1, ohne Leg-Verlust 2, mit Average 3 Sterne', () {
    final c = ChallengeCatalog.byId('c2-1')!;
    expect(c.starsFor({'won': 0, 'legsLost': 0, 'average': 90}), 0);
    expect(c.starsFor({'won': 1, 'legsLost': 1, 'average': 90}), 1);
    expect(c.starsFor({'won': 1, 'legsLost': 0, 'average': 40}), 2);
    expect(c.starsFor({'won': 1, 'legsLost': 0, 'average': 70}), 3);
    final setup = c.matchSetup(playerName: 'Ben', profileId: 1);
    expect(setup.players, hasLength(2));
    expect(setup.players.last.isBot, isTrue);
    expect(setup.format.legsToWin, 2);
  });

  test('Live-Sterne: Darts steigen (sicher verloren), Punkte steigen (sicher erreicht), Bob\'s vorläufig', () {
    final atc = ChallengeCatalog.byId('c1-1')!; // ≤ 60/40/25 Darts
    expect(atc.liveStars({'darts': 40}, over: false), [StarState.open, StarState.open, StarState.lost]);
    final points = ChallengeCatalog.byId('c1-3')!; // ≥ 350/500/800
    expect(points.liveStars({'points': 520}, over: false), [StarState.reached, StarState.reached, StarState.open]);
    final bobs = ChallengeCatalog.byId('c2-7')!; // ≥ 1/100/300, kann fallen
    expect(bobs.liveStars({'score': 150}, over: false), [StarState.provisional, StarState.provisional, StarState.open]);
    final countdown = ChallengeCatalog.byId('c3-7')!; // ≤ 220/110/0, fällt
    expect(countdown.liveStars({'score': 200}, over: false), [StarState.reached, StarState.open, StarState.open]);
    expect(atc.liveStars({'darts': 40, 'completed': 1}, over: true), [StarState.reached, StarState.reached, StarState.lost]);
  });

  test('Wertung: nicht beendete Spiele mit Pflicht-Ende zählen nicht', () {
    final bobs = ChallengeCatalog.byId('c2-7')!;
    expect(bobs.starsFor({'score': 350, 'completed': 0}), 0);
    expect(bobs.scoreOf({'score': 350, 'completed': 0}), isNull);
    expect(bobs.starsFor({'score': 350, 'completed': 1}), 3);
    expect(bobs.better(20, 10), isTrue);
    final atc = ChallengeCatalog.byId('c1-1')!;
    expect(atc.better(30, 40), isTrue);
    expect(atc.better(50, null), isTrue);
  });

  group('Fortschritt', () {
    ChallengeBest r(String id, int stars) =>
        ChallengeBest(challengeId: id, stars: stars, attempts: 1, achievedAt: DateTime(2026, 10, 1));

    test('Kapitel 1 offen, erste Challenge offen, weitere nach einem Stern in einer der beiden davor', () {
      final p0 = ChallengeProgress(const []);
      expect(p0.chapterUnlocked(ChallengeChapter.beginner), isTrue);
      expect(p0.chapterUnlocked(ChallengeChapter.amateur), isFalse);
      expect(p0.unlocked(ChallengeCatalog.byId('c1-1')!), isTrue);
      expect(p0.unlocked(ChallengeCatalog.byId('c1-2')!), isFalse);

      final p1 = ChallengeProgress([r('c1-1', 1)]);
      expect(p1.unlocked(ChallengeCatalog.byId('c1-2')!), isTrue);
      // Über c1-2 hinweg: c1-3 ist offen, weil c1-1 einen Stern hat.
      expect(p1.unlocked(ChallengeCatalog.byId('c1-3')!), isTrue);
      expect(p1.unlocked(ChallengeCatalog.byId('c1-4')!), isFalse);
      expect(p1.nextAfter(ChallengeCatalog.byId('c1-1')!)!.id, 'c1-2');
    });

    test('12 Sterne im Kapitel schalten das nächste frei', () {
      final eleven = ChallengeProgress([r('c1-1', 3), r('c1-2', 3), r('c1-3', 3), r('c1-4', 2)]);
      expect(eleven.chapterStars(ChallengeChapter.beginner), 11);
      expect(eleven.chapterUnlocked(ChallengeChapter.amateur), isFalse);
      final twelve = ChallengeProgress([r('c1-1', 3), r('c1-2', 3), r('c1-3', 3), r('c1-4', 3)]);
      expect(twelve.chapterUnlocked(ChallengeChapter.amateur), isTrue);
      expect(twelve.unlocked(ChallengeCatalog.byId('c2-1')!), isTrue);
      expect(twelve.chapterUnlocked(ChallengeChapter.league), isFalse);
      expect(twelve.totalStars, 12);
      expect(ChallengeProgress.maxStars(ChallengeChapter.beginner), 24);
    });
  });
}
