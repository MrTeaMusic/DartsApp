import '../../../core/l10n.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../domain/match_format.dart';
import '../domain/x01_match.dart';

/// Texte des Match-Bereichs, die aus Domänen-Werten entstehen.
extension MatchTexts on AppLocalizations {
  String matchEventText(MatchEvent e, List<String> names) {
    final name = names[e.player];
    return switch (e.type) {
      MatchEventType.bust => matchEvBust(name),
      MatchEventType.legWon => matchEvLeg(name, e.value ?? 0),
      MatchEventType.setWon => matchEvSet(name),
      MatchEventType.matchWon => matchEvMatch(name),
      MatchEventType.max => matchEv180(name),
    };
  }

  String tourRoundName(int round) => switch (round) {
    0 => tourRound0,
    1 => tourRound1,
    2 => tourRound2,
    _ => tourRound3,
  };

  String outModeLabel(OutMode m) => switch (m) {
    OutMode.straight => matchOutStraight,
    OutMode.double => matchOutDouble,
    OutMode.master => matchOutMaster,
  };

  String formatLabel(MatchFormat f) =>
      f.usesSets ? matchFormatSets(f.setsToWin, f.legsToWin) : matchFormatLegs(f.legsToWin, f.bestOf);

  /// Grobe Einordnung eines 3-Dart-Averages.
  String averageLevel(double average) {
    if (average < 40) return matchLevelBeginner;
    if (average < 60) return matchLevelHobby;
    if (average < 80) return matchLevelLeague;
    if (average < 97) return matchLevelPro;
    return matchLevelTop;
  }
}
