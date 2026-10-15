import '../../../core/l10n.dart';
import '../../autodarts_live/presentation/autodarts_live_controller.dart';
import '../../board/domain/segment.dart';
import '../../board/presentation/live_visit_controller.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../games/presentation/game_texts.dart';
import '../../matches/domain/x01_match.dart';
import '../../matches/presentation/match_controller.dart';
import '../../matches/presentation/match_texts.dart';
import '../domain/screen_state.dart';

/// Baut aus dem Zustand der laufenden Spiele den [ScreenState] für den
/// zweiten Bildschirm. Reine Umwandlung ohne Riverpod, damit sie sich für
/// jede Spielart einzeln testen lässt; aufgerufen wird sie nur, wenn ein
/// Viewer verbunden ist (höchstens ein paar Mal pro Sekunde).
abstract final class ScreenSnapshot {
  /// Trainingsspiel. [visit] sind die Darts der laufenden Aufnahme, wie das
  /// Board sie zeigt (inklusive ignorierter Darts nach Bust/Checkout).
  static ScreenState training(AppLocalizations l10n, ActiveGame active, {required LiveVisitState visit, String? playerName}) {
    final game = active.game;
    final display = game.display;
    final records = active.session.records;
    final thrown = visit.visit.length.clamp(0, records.length);
    final ended = active.ended;
    final waiting = ended || (game.visitClosed && thrown > 0);
    final route = waiting ? null : display.suggestion;
    final setup = route == null && !waiting ? display.setup : null;

    // Letzte abgeschlossene Aufnahme: die Darts vor der laufenden mit
    // demselben Aufnahme-Index.
    final before = records.sublist(0, records.length - thrown);
    final last = before.isEmpty ? const <DartThrow>[] : [
      for (final r in before.reversed.takeWhile((r) => r.visitIndex == before.last.visitIndex).toList().reversed) r.dart,
    ];
    final summary = ended ? game.result.summary : const <GameStat>[];
    // Wichtigstes Ereignis: „Checkout“ statt des folgenden „Spiel vorbei“.
    final event = active.events.reversed.where((e) => eventTone(e.type) != EventTone.neutral).firstOrNull ?? active.events.lastOrNull;
    final current = [for (final d in visit.visit) d];

    return ScreenState(
      kind: ScreenKind.training,
      title: l10n.gameTitle(active.gameId),
      subtitle: playerName,
      players: [
        ScreenPlayer(
          name: playerName ?? '',
          score: summary.isNotEmpty ? summary.first.value : display.headline,
          scoreLabel: summary.isNotEmpty ? l10n.statLabel(summary.first.key) : l10n.statLabel(display.headlineKey),
          active: !ended,
          darts: game.dartsThrown,
        ),
      ],
      visit: _names(current),
      visitScore: _sum(current),
      lastVisit: _names(last),
      lastVisitScore: last.isEmpty ? null : _sum(last),
      route: _segments(route),
      setup: _segments(setup?.darts),
      setupLabel: setup == null ? null : l10n.visitSetup(setup.leave),
      stats: [for (final s in ended ? summary.skip(1) : display.stats) ScreenStat(l10n.statLabel(s.key), s.value)],
      hits: _hits(current.isNotEmpty ? current : last),
      hitSerial: records.length,
      banner: event == null ? null : l10n.eventText(event),
      bannerTone: event == null ? ScreenTone.neutral : _tone(eventTone(event.type)),
      progress: display.progress,
      progressLabel: display.progressLabel,
      finished: ended,
    );
  }

  /// X01-Match (auch Turnier). [round] ist der Name der Turnierrunde.
  static ScreenState match(AppLocalizations l10n, MatchState state, {String? round}) {
    final m = state.match;
    final setup = state.setup;
    final format = setup.format;
    final names = [for (final p in setup.players) p.name];
    final ended = state.ended || m.finished;
    final records = state.session.records;
    final visit = [for (final i in state.session.currentVisitIndexes) records[i].dart];
    final route = ended || m.visitClosed ? null : m.suggestion;
    final setupPlan = route == null && !ended && !m.visitClosed ? m.setup : null;

    // Letzte Aufnahme: die Darts direkt vor der laufenden (anderer Spieler
    // bzw. vorherige Aufnahme).
    final start = records.length - visit.length;
    final last = <DartThrow>[];
    if (start > 0) {
      final serial = records[start - 1].visitSerial;
      for (var i = start - 1; i >= 0 && records[i].visitSerial == serial; i--) {
        last.insert(0, records[i].dart);
      }
    }

    final current = setup.players[m.current];
    final next = setup.players[m.nextPlayer];
    final soloHuman = setup.players.where((p) => !p.isBot).length == 1;
    final String? status = ended
        ? null
        : m.visitClosed && m.nextPlayer != m.current
            ? (soloHuman && !next.isBot ? l10n.matchWaitTakeoutYou : l10n.matchWaitTakeout(next.name))
            : current.isBot
                ? l10n.matchBotThrowing(current.name)
                : l10n.matchTurnOf(current.name);

    MatchEvent? event;
    for (final t in const [
      MatchEventType.matchWon,
      MatchEventType.setWon,
      MatchEventType.legWon,
      MatchEventType.bust,
      MatchEventType.max,
    ]) {
      event ??= state.events.where((e) => e.type == t).firstOrNull;
    }

    final legLabel = format.usesSets ? l10n.matchLegSetNumber(m.setNumber, m.legNumber) : l10n.matchLegNumber(m.legNumber);
    return ScreenState(
      kind: ScreenKind.match,
      title: round != null ? '${l10n.tournamentTitle} · $round' : '${format.startScore} · ${l10n.gameMatchX01}',
      subtitle: [l10n.formatLabel(format), if (!ended) legLabel].join(' · '),
      status: status,
      players: [
        for (var i = 0; i < setup.players.length; i++)
          ScreenPlayer(
            name: names[i],
            score: '${m.players[i].remaining}',
            scoreLabel: l10n.statRemaining,
            active: !ended && m.current == i,
            bot: setup.players[i].isBot,
            winner: m.winner == i,
            starter: !ended && m.legStarter == i,
            legs: format.usesSets ? m.players[i].legs : m.players[i].totalLegs,
            sets: format.usesSets ? m.players[i].sets : null,
            average: formatDecimal(m.players[i].average),
            darts: m.players[i].darts,
            lastVisit: m.players[i].lastVisit,
          ),
      ],
      visit: _names(visit),
      visitScore: m.visitScore,
      bust: m.visitBust,
      lastVisit: _names(last),
      lastVisitScore: last.isEmpty ? null : _sum(last),
      route: _segments(route),
      setup: _segments(setupPlan?.darts),
      setupLabel: setupPlan == null ? null : l10n.visitSetup(setupPlan.leave),
      hits: _hits(visit.isNotEmpty ? visit : last),
      hitSerial: records.length,
      banner: event == null ? null : l10n.matchEventText(event, names),
      bannerTone: switch (event?.type) {
        null => ScreenTone.neutral,
        MatchEventType.bust => ScreenTone.negative,
        _ => ScreenTone.positive,
      },
      finished: ended,
    );
  }

  /// Mitschreiben vom Board, mit oder ohne „X01 mitzählen“.
  static ScreenState live(AppLocalizations l10n, LiveViewState view, {String? playerName}) {
    final x = view.x01;
    final current = view.current;
    final last = view.lastVisit ?? const <DartThrow>[];
    final stats = view.stats;
    final event = x?.lastEvent;
    final checkout = x != null && event == GameEventType.checkout && x.legs.isNotEmpty ? x.legs.last.checkout : null;
    final route = x == null || x.dartsLeft == 0 ? null : x.suggestion;
    final setup = x == null || x.dartsLeft == 0 || route != null ? null : x.setup;

    return ScreenState(
      kind: ScreenKind.live,
      title: x == null ? l10n.liveTitle : '${l10n.liveTitleX01} · ${x.config.startScore}',
      subtitle: playerName,
      status: view.stats.isEmpty && current.isEmpty ? l10n.liveWaiting : null,
      players: [
        ScreenPlayer(
          name: playerName ?? '',
          score: x != null ? '${x.remaining}' : '${_sum(current)}',
          scoreLabel: x != null ? l10n.statRemaining : l10n.statVisitScore,
          active: true,
          legs: x?.legsWon,
          average: formatDecimal(x?.average ?? stats.rawAverage),
          darts: x?.darts ?? stats.darts,
          lastVisit: last.isEmpty ? null : _sum(last),
        ),
      ],
      visit: _names(current),
      visitScore: _sum(current),
      bust: event == GameEventType.bust,
      lastVisit: _names(last),
      lastVisitScore: last.isEmpty ? null : _sum(last),
      route: _segments(route),
      setup: _segments(setup?.darts),
      setupLabel: setup == null ? null : l10n.visitSetup(setup.leave),
      stats: [
        ScreenStat(l10n.statAverage, formatDecimal(x?.average ?? stats.rawAverage)),
        ScreenStat(l10n.statDarts, '${x?.darts ?? stats.darts}'),
        if (x != null) ScreenStat(l10n.liveLegs, l10n.liveLegsValue(x.legsWon, x.legsLost)),
        ScreenStat(l10n.statBestVisit, stats.isEmpty ? '–' : '${stats.bestVisit}'),
        if (stats.count180 > 0) ScreenStat(l10n.statLabel('count180'), '${stats.count180}'),
      ],
      hits: _hits(current.isNotEmpty ? current : last),
      hitSerial: view.dartSerial,
      banner: event == null ? null : l10n.eventText(GameEvent(event, value: checkout)),
      bannerTone: event == null ? ScreenTone.neutral : _tone(eventTone(event)),
    );
  }

  static List<String> _names(List<DartThrow> darts) => [for (final d in darts) d.segment.name];
  static List<String> _segments(List<Segment>? s) => s == null ? const [] : [for (final x in s) x.name];
  static int _sum(List<DartThrow> darts) => darts.fold(0, (a, d) => a + d.score);

  static List<ScreenHit> _hits(List<DartThrow> darts) => [
        for (final d in darts) ScreenHit(d.segment.name, x: d.position?.x, y: d.position?.y),
      ];

  static ScreenTone _tone(EventTone t) => switch (t) {
        EventTone.positive => ScreenTone.positive,
        EventTone.negative => ScreenTone.negative,
        EventTone.neutral => ScreenTone.neutral,
      };
}
