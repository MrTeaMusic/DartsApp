import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../games/presentation/active_game_controller.dart';
import '../../matches/domain/match_result.dart';
import '../../matches/domain/match_session.dart';
import '../../matches/presentation/match_controller.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/challenge_repository.dart';
import '../domain/challenge.dart';
import '../domain/challenge_catalog.dart';

/// Eine laufende Challenge und, nach dem Ende, ihr Ausgang.
@immutable
class ChallengeRun {
  const ChallengeRun({required this.challenge, required this.playerId, this.sessionId, this.match, this.outcome, this.aborted = false});

  final Challenge challenge;
  final int playerId;

  /// Session des Trainingsspiels.
  final int? sessionId;

  /// Das Match (bei Challenges gegen den Computer).
  final MatchSession? match;

  /// Ergebnis nach regulärem Ende.
  final ChallengeOutcome? outcome;

  /// Vorzeitig beendet: keine Wertung.
  final bool aborted;

  bool get done => outcome != null || aborted;

  bool ownsGame(ActiveGame? game) => game != null && sessionId != null && game.sessionId == sessionId;
  bool ownsMatch(MatchState? state) => state != null && match != null && identical(state.session, match);

  ChallengeRun copyWith({ChallengeOutcome? outcome, bool? aborted}) => ChallengeRun(
        challenge: challenge,
        playerId: playerId,
        sessionId: sessionId,
        match: match,
        outcome: outcome ?? this.outcome,
        aborted: aborted ?? this.aborted,
      );
}

final challengeRunProvider = NotifierProvider<ChallengeRunController, ChallengeRun?>(ChallengeRunController.new);

/// Startet Challenges über den [ActiveGameController] bzw. den
/// [MatchController] und wertet sie am Ende aus: Sterne, Bestwert und was
/// dadurch freigeschaltet wurde.
class ChallengeRunController extends Notifier<ChallengeRun?> {
  Future<void> _pending = Future.value();

  @override
  ChallengeRun? build() {
    ref.listen(activeGameProvider, (_, next) {
      final run = state;
      if (run == null || run.done || !run.ownsGame(next) || !next!.ended) return;
      if (!next.game.finished) {
        state = run.copyWith(aborted: true);
        return;
      }
      _pending = _record(run, next.game.result.metrics);
    });
    ref.listen(matchControllerProvider, (_, next) {
      final run = state;
      if (run == null || run.done || !run.ownsMatch(next) || !next!.ended) return;
      final human = next.setup.players.indexWhere((p) => !p.isBot);
      _pending = _record(run, matchResultFor(next.match, human, next.setup).metrics);
    });
    return null;
  }

  /// Wartet auf das Speichern des Ergebnisses (für Tests).
  @visibleForTesting
  Future<void> get pending => _pending;

  /// Startet die Challenge [challenge] (ein laufendes Spiel wird vorher
  /// gespeichert bzw. ein Match verlassen).
  Future<void> start(Challenge challenge) async {
    final playerId = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
    if (challenge.isMatch) {
      final name = ref.read(activePlayerProvider)?.name ?? 'Ich';
      // Ein offenes Trainingsspiel würde sonst parallel weiterlaufen.
      if (ref.read(activeGameProvider) != null) await ref.read(activeGameProvider.notifier).close();
      final matches = ref.read(matchControllerProvider.notifier);
      await matches.start(challenge.matchSetup(playerName: name, profileId: playerId));
      state = ChallengeRun(challenge: challenge, playerId: playerId, match: ref.read(matchControllerProvider)?.session);
      return;
    }
    // Ein offenes Match würde die Darts sonst mitzählen.
    await ref.read(matchControllerProvider.notifier).close();
    final def = challenge.definition;
    if (def == null) return;
    final games = ref.read(activeGameProvider.notifier);
    await games.start(def, challenge.config);
    state = ChallengeRun(challenge: challenge, playerId: playerId, sessionId: ref.read(activeGameProvider)?.sessionId);
  }

  /// Challenge beenden (z. B. beim Verlassen des Spiels).
  void clear() => state = null;

  Future<void> _record(ChallengeRun run, Map<String, num> metrics) async {
    final repo = ref.read(challengeRepositoryProvider);
    final c = run.challenge;
    final stars = c.starsFor(metrics);
    final score = c.scoreOf(metrics);
    final before = ChallengeProgress(await repo.results(run.playerId));
    final previous = await repo.record(run.playerId, c, stars: stars, score: score);
    final after = ChallengeProgress(await repo.results(run.playerId));
    Challenge? unlocked;
    for (final x in ChallengeCatalog.all) {
      if (!before.unlocked(x) && after.unlocked(x)) {
        unlocked = x;
        break;
      }
    }
    ChallengeChapter? chapter;
    for (final ch in ChallengeChapter.values) {
      if (!before.chapterUnlocked(ch) && after.chapterUnlocked(ch)) chapter = ch;
    }
    final newBest = previous == null
        ? stars > 0 || score != null
        : stars > previous.stars || (score != null && c.better(score, previous.best));
    final outcome = ChallengeOutcome(
      challenge: c,
      stars: stars,
      score: score,
      previous: previous,
      newBest: newBest,
      unlockedChallenge: unlocked,
      unlockedChapter: chapter,
    );
    final now = state;
    if (now != null && identical(now.challenge, c) && now.sessionId == run.sessionId && identical(now.match, run.match)) {
      state = now.copyWith(outcome: outcome);
    }
  }
}

/// Die nächste offene Challenge nach [c] laut aktuellem Fortschritt.
Challenge? nextChallenge(Challenge c, List<ChallengeBest> results) => ChallengeProgress(results).nextAfter(c);

/// Für `unawaited`-Aufrufe aus der Oberfläche.
void startChallenge(WidgetRef ref, Challenge c) => unawaited(ref.read(challengeRunProvider.notifier).start(c));
