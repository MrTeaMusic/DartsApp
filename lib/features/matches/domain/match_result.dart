import '../../games/domain/engine/game_display.dart';
import 'match_session.dart';
import 'x01_match.dart';

/// Spiel-ID, unter der die Würfe der Menschen aus Matches gespeichert werden.
/// Beginnt mit „x01“, damit Aufnahmen in Punkteverteilung und Konstanz
/// eingehen; der 3-Dart-Average kommt aus der Kennzahl `average`.
const String matchGameId = 'x01_match';

/// Ergebnis eines Spielers für Speicherung und Statistik. Nur die eigenen
/// Darts zählen, die des Gegners (Bot oder Mensch) nicht.
GameResult matchResultFor(X01Match m, int player, MatchSetup setup) {
  final p = m.players[player];
  final avg = p.average;
  final first9 = p.first9Average;
  final rate = p.checkoutRate;
  final lost = m.legs.length - p.totalLegs;
  final opponents = [
    for (var i = 0; i < setup.players.length; i++)
      if (i != player) setup.players[i].name,
  ];
  return GameResult(
    metrics: {
      'darts': p.darts,
      'average': avg ?? 0,
      'first9': ?first9,
      'first9Average': first9 ?? 0,
      'legsWon': p.totalLegs,
      'legsLost': lost,
      'legs': m.legs.length,
      if (setup.format.usesSets) 'setsWon': p.sets,
      'won': m.winner == player ? 1 : 0,
      if (p.highestFinish > 0) 'highestCheckout': p.highestFinish,
      'highestFinish': p.highestFinish,
      'bestLegDarts': ?p.bestLegDarts,
      'checkoutDarts': p.checkoutDarts,
      'checkoutRate': rate ?? 0,
      'count100': p.count100,
      'count140': p.count140,
      'count180': p.count180,
      'busts': p.busts,
      'completed': m.finished ? 1 : 0,
    },
    summary: [
      GameStat('average', formatDecimal(avg)),
      GameStat('first9Average', formatDecimal(first9)),
      GameStat('legsWon', '${p.totalLegs}/${m.legs.length}'),
      GameStat('checkoutRate', formatPercent(rate)),
      GameStat('highestFinish', p.highestFinish == 0 ? '–' : '${p.highestFinish}'),
      GameStat('scores100', '${p.count100} / ${p.count140} / ${p.count180}'),
    ],
    details: {
      'opponents': opponents,
      'format': setup.format.toJson(),
      'won': m.winner == player,
      if (setup.tournamentMatch != null) 'tournamentMatch': setup.tournamentMatch,
      // Für den Spielverlauf: wer man selbst war, Ergebnis aller Teilnehmer
      // und jedes Leg (Würfe der Gegner werden nicht gespeichert).
      'player': player,
      'players': [
        for (var i = 0; i < setup.players.length; i++)
          {
            'name': setup.players[i].name,
            'bot': setup.players[i].isBot,
            'botAverage': ?setup.players[i].botAverage,
            ...matchPlayerStats(m.players[i]),
          },
      ],
      'legs': [
        for (final l in m.legs)
          {'winner': l.winner, 'set': l.set, 'darts': l.darts, 'checkout': l.checkout, 'visit': l.visit},
      ],
    },
  );
}

/// Kennzahlen eines Teilnehmers für das gespeicherte Ergebnis.
Map<String, Object?> matchPlayerStats(MatchPlayerState p) => {
  'legs': p.totalLegs,
  'sets': p.sets,
  'darts': p.darts,
  'average': ?p.average,
  'first9': ?p.first9Average,
  'checkoutRate': ?p.checkoutRate,
  'highestFinish': p.highestFinish,
  'bestLegDarts': ?p.bestLegDarts,
  'count100': p.count100,
  'count140': p.count140,
  'count180': p.count180,
};
