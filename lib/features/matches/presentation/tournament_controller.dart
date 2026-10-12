import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/match_store.dart';
import '../domain/cpu_players.dart';
import '../domain/match_session.dart';
import '../domain/tournament.dart';
import '../domain/x01_match.dart';
import 'match_controller.dart';

/// Liste der Computergegner (bearbeitbar, gespeichert in den Einstellungen).
final cpuPlayersProvider = NotifierProvider<CpuPlayersController, List<CpuPlayer>>(CpuPlayersController.new);

class CpuPlayersController extends Notifier<List<CpuPlayer>> {
  @override
  List<CpuPlayer> build() => ref.watch(matchStoreProvider).cpuPlayers();

  Future<void> save(List<CpuPlayer> players) async {
    state = List.unmodifiable(players);
    await ref.read(matchStoreProvider).saveCpuPlayers(players);
  }

  Future<void> upsert(int? index, CpuPlayer player) {
    final list = [...state];
    if (index == null || index < 0 || index >= list.length) {
      list.add(player);
    } else {
      list[index] = player;
    }
    return save(list);
  }

  Future<void> remove(int index) {
    final list = [...state]..removeAt(index);
    return save(list);
  }

  Future<void> reset() async {
    await ref.read(matchStoreProvider).resetCpuPlayers();
    state = defaultCpuPlayers;
  }
}

/// Das aktuelle Turnier (eines je Gerät), `null` ohne Turnier.
final tournamentControllerProvider = NotifierProvider<TournamentController, Tournament?>(TournamentController.new);

class TournamentController extends Notifier<Tournament?> {
  @override
  Tournament? build() => ref.watch(matchStoreProvider).tournament();

  MatchStore get _store => ref.read(matchStoreProvider);

  Future<void> _save() async {
    ref.notifyListeners();
    await _store.saveTournament(state);
  }

  /// Neues Turnier; ein laufendes wird verworfen.
  Future<void> create({
    required String humanName,
    int? profileId,
    required double difficulty,
    required List<int> bestOf,
    int? seed,
  }) async {
    await _discardSavedMatch();
    state = Tournament.create(
      humanName: humanName,
      profileId: profileId,
      pool: ref.read(cpuPlayersProvider),
      difficulty: difficulty,
      bestOf: bestOf,
      seed: seed ?? ref.read(botRandomProvider).nextInt(1 << 31),
    );
    await _save();
  }

  /// Turnier löschen.
  Future<void> discard() async {
    await _discardSavedMatch();
    state = null;
    await _store.saveTournament(null);
  }

  Future<void> _discardSavedMatch() async {
    final saved = _store.currentMatch();
    if (saved?.setup.tournamentMatch != null) await _store.saveCurrentMatch(null);
  }

  /// Setup für das nächste Spiel des Menschen.
  MatchSetup? nextMatchSetup() {
    final t = state;
    final m = t?.humanMatch;
    if (t == null || m == null) return null;
    MatchPlayer player(int e) {
      final entrant = t.entrants[e];
      return entrant.isHuman
          ? MatchPlayer.human(entrant.name, profileId: entrant.profileId)
          : MatchPlayer.bot(entrant.name, average: t.botAverage(e));
    }

    return MatchSetup(
      format: t.formatFor(m.round),
      players: [player(m.a!), player(m.b!)],
      // Wie das Ausbullen: zufällig, wer anfängt.
      firstStarter: ref.read(botRandomProvider).nextInt(2),
      tournamentMatch: '${t.id}/${m.id}',
    );
  }

  /// Gespeichertes, unterbrochenes Spiel dieses Turniers.
  SavedMatch? savedMatch() {
    final t = state;
    final saved = _store.currentMatch();
    final m = t?.humanMatch;
    if (t == null || saved == null || m == null) return null;
    return saved.setup.tournamentMatch == '${t.id}/${m.id}' ? saved : null;
  }

  /// Ergebnis eines gespielten Matches eintragen; danach werden die übrigen
  /// Spiele der Runde simuliert.
  Future<void> recordMatch(String tournamentMatch, X01Match result) async {
    final t = state;
    if (t == null || !result.finished) return;
    final parts = tournamentMatch.split('/');
    if (parts.length != 2 || parts.first != t.id) return;
    final m = t.matchById(parts.last);
    if (m == null || m.played || !m.ready) return;
    final winner = result.winner == 0 ? m.a! : m.b!;
    t.record(m, winner: winner, scoreA: result.players[0].totalLegs, scoreB: result.players[1].totalLegs);
    t.simulateRound(ref.read(botRandomProvider));
    await _save();
  }

  /// Nächste Runde ohne den Menschen simulieren (nach dem Ausscheiden).
  Future<void> simulateRound() async {
    final t = state;
    if (t == null || t.finished) return;
    t.simulateRound(ref.read(botRandomProvider));
    await _save();
  }

  /// Restliches Turnier simulieren.
  Future<void> simulateToEnd() async {
    final t = state;
    if (t == null) return;
    final random = ref.read(botRandomProvider);
    while (!t.finished && t.humanMatch == null) {
      if (t.simulateRound(random) == 0) break;
    }
    await _save();
  }
}
