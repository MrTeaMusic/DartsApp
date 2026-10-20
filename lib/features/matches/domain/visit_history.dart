import '../../board/domain/segment.dart';
import '../../games/domain/engine/game_session.dart';
import '../../games/domain/games/x01_solo.dart';
import 'match_session.dart';

/// Ein gezählter oder ignorierter Dart, so wie ihn die X01-Engines melden.
///
/// Die Engines (Match und X01-Solo) liefern pro Dart den Rest danach und ob
/// der Dart einen Bust ausgelöst hat; die Regeln (Double-In, Out-Modus, Bust)
/// stecken allein dort. Aus diesen Angaben baut [VisitHistory] die Tabelle
/// der Aufnahmen, ohne etwas nachzurechnen.
class VisitDart {
  const VisitDart({
    required this.player,
    required this.leg,
    required this.visit,
    required this.counted,
    required this.segment,
    required this.remaining,
    this.bust = false,
    this.legEnd = false,
  });

  /// Spieler (Index), im Solo-Spiel immer 0.
  final int player;

  /// Leg-Nummer (ab 1).
  final int leg;

  /// Nummer der Aufnahme; Darts einer Aufnahme teilen sie.
  final int visit;

  /// `false`: nach Bust/Checkout geworfen und von der Engine ignoriert.
  final bool counted;
  final Segment segment;

  /// Rest des Spielers nach diesem Dart (0 beim Checkout, nach Bust der
  /// Rest vor der Aufnahme).
  final int remaining;

  /// Dieser Dart war der Bust.
  final bool bust;

  /// Dieser Dart hat das Leg beendet (Checkout, im Solo auch Dart-Limit).
  final bool legEnd;

  bool get checkout => legEnd && remaining == 0;
}

/// Eine abgeschlossene Aufnahme eines Spielers.
class VisitRow {
  const VisitRow({
    required this.player,
    required this.leg,
    required this.visit,
    required this.darts,
    required this.points,
    required this.remaining,
    required this.bust,
    required this.checkout,
  });

  final int player;
  final int leg;

  /// Nummer der Aufnahme, eindeutig im Match bzw. Spiel.
  final int visit;

  /// Die gezählten Darts der Aufnahme.
  final List<Segment> darts;

  /// Abgezogene Punkte, 0 nach Bust (und bei Double-In vor dem ersten Double).
  final int points;

  /// Rest nach der Aufnahme (nach Bust unverändert).
  final int remaining;
  final bool bust;

  /// Die Aufnahme hat das Leg gecheckt.
  final bool checkout;
}

/// Die Aufnahmen eines Matches bzw. Solo-Spiels, aus den Dart-Aufzeichnungen
/// abgeleitet. Es gibt keinen eigenen Zustand: Rückgängig, Korrekturen und
/// Legwechsel ergeben sich daraus, dass die Aufzeichnungen neu abgespielt
/// werden.
class VisitHistory {
  const VisitHistory._(this._rows, this.currentLeg);

  /// Leere Tabelle (Leg 1).
  static const VisitHistory empty = VisitHistory._([], 1);

  /// Baut die Aufnahmen aus [darts] in Wurfreihenfolge.
  ///
  /// [startScore] ist der Startwert eines Legs (für die Punkte der ersten
  /// Aufnahme). [openVisit] ist die Nummer der Aufnahme, die noch geworfen
  /// wird (`null`: keine); sie erscheint noch nicht in der Tabelle, ihre
  /// Darts stehen auf der Aufnahme-Karte.
  factory VisitHistory.from(Iterable<VisitDart> darts, {required int startScore, int? openVisit}) {
    final rows = <VisitRow>[];
    // Letzte Aufnahme je Spieler: ihr Rest ist der Stand vor der nächsten.
    final lastOf = <int, VisitRow>{};
    var leg = 1;

    final group = <VisitDart>[];
    void flush() {
      if (group.isEmpty) return;
      final first = group.first;
      final last = group.last;
      final prev = lastOf[first.player];
      final before = prev != null && prev.leg == first.leg ? prev.remaining : startScore;
      final bust = group.any((d) => d.bust);
      final row = VisitRow(
        player: first.player,
        leg: first.leg,
        visit: first.visit,
        darts: [for (final d in group) d.segment],
        points: bust ? 0 : before - last.remaining,
        remaining: last.remaining,
        bust: bust,
        checkout: last.checkout,
      );
      rows.add(row);
      lastOf[first.player] = row;
      group.clear();
    }

    for (final d in darts) {
      if (!d.counted) continue;
      leg = d.leg;
      if (group.isNotEmpty && (group.first.visit != d.visit || group.first.player != d.player)) flush();
      group.add(d);
    }
    if (group.isNotEmpty && group.first.visit != openVisit) flush();
    return VisitHistory._(rows, leg);
  }

  /// Aus den Aufzeichnungen eines Matches.
  factory VisitHistory.ofMatch(MatchSession session) {
    final m = session.match;
    return VisitHistory.from(
      [
        for (final r in session.records)
          VisitDart(
            player: r.player,
            leg: r.leg,
            visit: r.visitSerial,
            counted: r.counted,
            segment: r.dart.segment,
            remaining: r.outcome.remaining,
            bust: r.outcome.bust,
            legEnd: r.outcome.counted && r.outcome.remaining == 0,
          ),
      ],
      startScore: session.setup.format.startScore,
      openVisit: m.visitClosed || m.finished ? null : m.visitSerial,
    );
  }

  /// Aus den Aufzeichnungen eines X01-Solo-Spiels (Spieler 0).
  factory VisitHistory.ofSolo(GameSession session, X01Solo game) {
    return VisitHistory.from(
      [
        for (final r in session.records)
          if (r.info is X01DartInfo)
            VisitDart(
              player: 0,
              leg: (r.info as X01DartInfo).leg,
              visit: r.visitIndex,
              counted: r.counted,
              segment: r.dart.segment,
              remaining: (r.info as X01DartInfo).remaining,
              bust: (r.info as X01DartInfo).bust,
              legEnd: (r.info as X01DartInfo).legEnd,
            ),
      ],
      startScore: game.startScore,
      openVisit: game.visitClosed || game.finished ? null : game.visitIndex,
    );
  }

  final List<VisitRow> _rows;

  /// Leg, dessen Tabelle gezeigt wird: das des letzten gezählten Darts. Nach
  /// einem gewonnenen Leg bleibt es bis zum ersten Dart des nächsten stehen,
  /// damit der Checkout noch zu sehen ist.
  final int currentLeg;

  /// Alle abgeschlossenen Aufnahmen, Wurfreihenfolge.
  List<VisitRow> get rows => List.unmodifiable(_rows);

  /// Die Aufnahmen von [player] im aktuellen Leg, die älteste zuerst.
  List<VisitRow> legRowsOf(int player) => [
    for (final r in _rows)
      if (r.player == player && r.leg == currentLeg) r,
  ];
}
