import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../games/domain/games/checkout/setup_advisor.dart';
import 'match_format.dart';

/// Was im Match gerade passiert ist. Die UI übersetzt den Typ in Text.
enum MatchEventType {
  /// Überworfen, Rest bleibt.
  bust,

  /// Leg gewonnen ([MatchEvent.value] = gecheckter Rest).
  legWon,

  /// Satz gewonnen.
  setWon,

  /// Match gewonnen.
  matchWon,

  /// 180 geworfen.
  max,
}

class MatchEvent {
  const MatchEvent(this.type, this.player, {this.value});
  final MatchEventType type;
  final int player;
  final int? value;

  @override
  bool operator ==(Object other) =>
      other is MatchEvent && other.type == type && other.player == player && other.value == value;

  @override
  int get hashCode => Object.hash(type, player, value);

  @override
  String toString() => 'MatchEvent($type, $player${value == null ? '' : ', $value'})';
}

/// Ein beendetes Leg.
class MatchLeg {
  const MatchLeg({required this.winner, required this.set, required this.darts, required this.checkout, this.visit = 0});
  final int winner;

  /// Satz (ab 1), 1 ohne Satzmodus.
  final int set;

  /// Gezählte Darts des Siegers in diesem Leg.
  final int darts;
  final int checkout;

  /// Aufnahme (wie [MatchDartOutcome.visitSerial]), mit der das Leg endete.
  /// Daran lassen sich gespeicherte Würfe den Legs zuordnen.
  final int visit;
}

/// Stand und Statistik eines Spielers im Match.
class MatchPlayerState {
  MatchPlayerState(this.remaining, {required this.opened});

  int remaining;
  bool opened;

  /// Legs im laufenden Satz (ohne Satzmodus: im Match).
  int legs = 0;
  int sets = 0;

  /// Alle gewonnenen Legs des Matches.
  int totalLegs = 0;

  /// Gezählte Darts und abgezogene Punkte (Bust-Aufnahmen zählen 0).
  int darts = 0;
  int points = 0;

  /// Summe und Anzahl der ersten neun Darts aller beendeten Legs.
  int first9Points = 0;
  int first9Darts = 0;

  /// Punkte je gezähltem Dart im laufenden Leg.
  final List<int> legDartPoints = [];

  /// Darts, die bei möglichem Finish (mit einem Dart) geworfen wurden.
  int checkoutDarts = 0;
  int highestFinish = 0;
  int? bestLegDarts;
  int busts = 0;

  /// Punkte der letzten abgeschlossenen Aufnahme (0 nach Bust).
  int? lastVisit;
  int count100 = 0;
  int count140 = 0;
  int count180 = 0;

  double? get average => darts == 0 ? null : points / darts * 3;

  /// Schnitt der ersten neun Darts je Leg, inklusive laufendem Leg.
  double? get first9Average {
    final live = legDartPoints.take(9).toList();
    final d = first9Darts + live.length;
    if (d == 0) return null;
    return (first9Points + live.fold<int>(0, (a, b) => a + b)) / d * 3;
  }

  /// Anteil gecheckter Legs an den Darts aufs Finish.
  double? get checkoutRate => checkoutDarts == 0 ? null : totalLegs / checkoutDarts;

  void _foldLeg() {
    final first = legDartPoints.take(9).toList();
    first9Points += first.fold<int>(0, (a, b) => a + b);
    first9Darts += first.length;
    legDartPoints.clear();
  }
}

/// Ergebnis eines Darts im Match.
class MatchDartOutcome {
  const MatchDartOutcome({
    required this.player,
    required this.counted,
    required this.visitSerial,
    required this.leg,
    required this.remaining,
    this.bust = false,
  });

  /// Wer geworfen hat.
  final int player;

  /// `false`, wenn der Dart nach Bust/Checkout ignoriert wurde.
  final bool counted;

  /// Fortlaufende Nummer der Aufnahme im Match (ab 0).
  final int visitSerial;

  /// Leg-Nummer im Match (ab 1).
  final int leg;

  /// Rest des Spielers nach dem Dart: 0 beim Checkout (vor dem Zurücksetzen
  /// fürs nächste Leg), nach einem Bust der Rest vor der Aufnahme.
  final int remaining;

  /// Dieser Dart hat die Aufnahme zum Bust gemacht.
  final bool bust;
}

/// X01-Match für zwei (oder mehr) Spieler im Wechsel. Reine Dart-Klasse.
///
/// * Jeder Spieler wirft eine Aufnahme mit bis zu drei Darts, dann ist der
///   nächste dran. Die Aufnahme endet nach drei Darts, Bust oder Checkout;
///   der Wechsel passiert mit [endVisit] (Takeout) oder spätestens mit dem
///   nächsten Dart nach drei geworfenen Darts (vergessener Takeout).
/// * Bust und erlaubter letzter Dart kommen aus [CheckoutRules], wie im
///   X01-Solo.
/// * Der Anwurf wechselt mit jedem Leg; im Satzmodus wechselt zusätzlich der
///   Anwurf jedes Satzes, innerhalb des Satzes dann wieder Leg für Leg.
/// * Mit [MatchFormat.setsToWin] = 0 gewinnt, wer zuerst
///   [MatchFormat.legsToWin] Legs hat, sonst wer zuerst so viele Sätze hat.
class X01Match {
  X01Match({required this.format, required this.playerCount, this.firstStarter = 0})
    : assert(playerCount >= 1),
      assert(firstStarter >= 0 && firstStarter < playerCount) {
    for (var i = 0; i < playerCount; i++) {
      players.add(MatchPlayerState(format.startScore, opened: !format.doubleIn));
    }
    current = firstStarter;
    legStarter = firstStarter;
    setStarter = firstStarter;
    _snapshot();
  }

  static const int dartsPerVisit = 3;

  final MatchFormat format;
  final int playerCount;
  final int firstStarter;
  final List<MatchPlayerState> players = [];

  /// Wer gerade wirft (bzw. die laufende Aufnahme geworfen hat).
  late int current;
  late int legStarter;
  late int setStarter;

  /// Gezählte Darts der laufenden Aufnahme.
  final List<DartThrow> visit = [];
  int visitSerial = 0;
  int _physical = 0;
  bool visitClosed = false;
  int _next = 0;

  int? winner;
  bool get finished => winner != null;

  /// Beendete Legs.
  final List<MatchLeg> legs = [];

  /// Ereignisse des letzten Darts bzw. Takeouts.
  final List<MatchEvent> events = [];

  int _visitStartRemaining = 0;
  bool _visitStartOpened = true;
  int _visitPoints = 0;
  bool _visitBust = false;

  /// Leg-Nummer im Match (ab 1).
  int get legNumber => legs.length + (finished ? 0 : 1);

  /// Satz-Nummer (ab 1), 1 ohne Satzmodus.
  int get setNumber => format.usesSets ? players.fold<int>(0, (a, p) => a + p.sets) + (finished ? 0 : 1) : 1;

  /// Körperlich geworfene Darts der laufenden Aufnahme (inkl. ignorierter).
  int get physicalDartsInVisit => _physical;

  /// Darts, die der aktuelle Spieler in dieser Aufnahme noch werfen kann.
  int get dartsLeft => visitClosed ? 0 : dartsPerVisit - visit.length;

  MatchPlayerState get currentPlayer => players[current];

  /// Wer nach dem Takeout dran ist.
  int get nextPlayer => visitClosed ? _next : current;

  /// Punkte der laufenden Aufnahme (0 nach Bust).
  int get visitScore => _visitBust ? 0 : _visitPoints;
  bool get visitBust => _visitBust;

  /// Checkout-Weg für den Spieler am Zug, `null` ohne mögliches Finish.
  List<Segment>? get suggestion {
    if (finished || visitClosed) return null;
    final p = currentPlayer;
    if (!p.opened) return null;
    return CheckoutRules.suggest(p.remaining, darts: dartsLeft, out: format.outMode);
  }

  /// Stell-Vorschlag für den Spieler am Zug, wenn kein Finish mehr geht.
  SetupPlan? get setup {
    if (finished || visitClosed) return null;
    final p = currentPlayer;
    if (!p.opened || suggestion != null) return null;
    return SetupAdvisor.suggest(p.remaining, darts: dartsLeft, out: format.outMode);
  }

  void _snapshot() {
    _visitStartRemaining = currentPlayer.remaining;
    _visitStartOpened = currentPlayer.opened;
    _visitPoints = 0;
    _visitBust = false;
  }

  /// Ein Dart des Spielers am Zug.
  MatchDartOutcome throwDart(DartThrow dart) {
    events.clear();
    if (finished) {
      return MatchDartOutcome(
        player: current,
        counted: false,
        visitSerial: visitSerial,
        leg: legNumber,
        remaining: currentPlayer.remaining,
      );
    }
    if (visitClosed && _physical >= dartsPerVisit) _advance();
    final leg = legNumber;
    _physical++;
    if (visitClosed) {
      return MatchDartOutcome(
        player: current,
        counted: false,
        visitSerial: visitSerial,
        leg: leg,
        remaining: currentPlayer.remaining,
      );
    }
    final who = current;
    visit.add(dart);
    _handle(dart);
    if (!visitClosed && visit.length >= dartsPerVisit) _close((current + 1) % playerCount);
    return MatchDartOutcome(
      player: who,
      counted: true,
      visitSerial: visitSerial,
      leg: leg,
      remaining: _remainingAfterDart,
      bust: _dartBust,
    );
  }

  /// Takeout bzw. „Weiter“: Aufnahme beenden, der nächste Spieler ist dran.
  /// Gibt `false` zurück, wenn es nichts zu beenden gab.
  bool endVisit() {
    events.clear();
    if (finished || (_physical == 0 && visit.isEmpty)) return false;
    if (!visitClosed) _close((current + 1) % playerCount);
    if (finished) return false;
    _advance();
    return true;
  }

  void _advance() {
    current = _next;
    visit.clear();
    _physical = 0;
    visitClosed = false;
    visitSerial++;
    _snapshot();
  }

  void _close(int next) {
    if (visitClosed) return;
    visitClosed = true;
    _next = next;
    final p = players[current];
    p.lastVisit = _visitBust ? 0 : _visitPoints;
    if (_visitBust) return;
    final v = _visitPoints;
    if (v == 180) {
      p.count180++;
      events.add(MatchEvent(MatchEventType.max, current));
    } else if (v >= 140) {
      p.count140++;
    } else if (v >= 100) {
      p.count100++;
    }
  }

  /// Rest des Werfers nach dem letzten Dart (vor dem Zurücksetzen fürs
  /// nächste Leg) und ob dieser Dart ein Bust war; für [MatchDartOutcome].
  int _remainingAfterDart = 0;
  bool _dartBust = false;

  void _handle(DartThrow dart) {
    final p = currentPlayer;
    final s = dart.segment;
    p.darts++;
    _dartBust = false;
    if (p.opened && CheckoutRules.isCheckout(p.remaining, darts: 1, out: format.outMode)) p.checkoutDarts++;
    if (!p.opened) {
      if (!s.isDouble) {
        p.legDartPoints.add(0);
        _remainingAfterDart = p.remaining;
        return;
      }
      p.opened = true;
    }
    if (CheckoutRules.isBust(p.remaining, s, format.outMode)) {
      p.legDartPoints.add(0);
      _bust(p);
      _remainingAfterDart = p.remaining;
      _dartBust = true;
      return;
    }
    p.remaining -= s.score;
    p.points += s.score;
    _visitPoints += s.score;
    p.legDartPoints.add(s.score);
    _remainingAfterDart = p.remaining;
    if (p.remaining == 0) _legWon(p);
  }

  void _bust(MatchPlayerState p) {
    p.busts++;
    p.points -= _visitPoints;
    for (var i = p.legDartPoints.length - visit.length; i < p.legDartPoints.length; i++) {
      if (i >= 0) p.legDartPoints[i] = 0;
    }
    _visitBust = true;
    p.remaining = _visitStartRemaining;
    p.opened = _visitStartOpened;
    events.add(MatchEvent(MatchEventType.bust, current, value: p.remaining));
    _close((current + 1) % playerCount);
  }

  void _legWon(MatchPlayerState p) {
    final checkout = _visitStartRemaining;
    final legDarts = p.legDartPoints.length;
    legs.add(MatchLeg(winner: current, set: setNumber, darts: legDarts, checkout: checkout, visit: visitSerial));
    p.legs++;
    p.totalLegs++;
    if (checkout > p.highestFinish) p.highestFinish = checkout;
    if (p.bestLegDarts == null || legDarts < p.bestLegDarts!) p.bestLegDarts = legDarts;
    events.add(MatchEvent(MatchEventType.legWon, current, value: checkout));
    for (final q in players) {
      q._foldLeg();
    }

    var newSet = false;
    if (p.legs >= format.legsToWin) {
      if (format.usesSets) {
        p.sets++;
        for (final q in players) {
          q.legs = 0;
        }
        events.add(MatchEvent(MatchEventType.setWon, current, value: p.sets));
        if (p.sets >= format.setsToWin) winner = current;
        newSet = true;
      } else {
        winner = current;
      }
    }
    if (winner != null) {
      events.add(MatchEvent(MatchEventType.matchWon, current));
      _close(current);
      return;
    }
    if (newSet) {
      setStarter = (setStarter + 1) % playerCount;
      legStarter = setStarter;
    } else {
      legStarter = (legStarter + 1) % playerCount;
    }
    // Den gecheckten Rest für die Anzeige der Aufnahme merken, dann alle
    // Spieler auf den Startwert setzen.
    for (final q in players) {
      q.remaining = format.startScore;
      q.opened = !format.doubleIn;
    }
    _close(legStarter);
  }
}
