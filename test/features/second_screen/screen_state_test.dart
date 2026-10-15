import 'dart:convert';

import 'package:dartlab/core/l10n.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/board/presentation/live_visit_controller.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/engine/game_session.dart';
import 'package:dartlab/features/games/domain/games/around_the_clock.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/second_screen/presentation/screen_snapshot.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

final l10n = lookupAppLocalizations(const Locale('de'));

/// Über JSON hin und zurück, wie zwischen Hub und Viewer.
ScreenState roundTrip(ScreenState s) => ScreenState.fromJson(jsonDecode(jsonEncode(s.toJson())));

DartThrow at(String name, double x, double y) =>
    DartThrow(segment: Segment.tryParse(name)!, position: BoardPoint(x, y), timestamp: DateTime(2026, 10, 15), source: DartSourceKind.autodartsLocal);

void main() {
  test('leerer Stand: nur Art und Version', () {
    expect(ScreenState.idle.toJson(), {'v': screenStateVersion, 'kind': 'idle'});
    final back = roundTrip(ScreenState.idle);
    expect(back.isIdle, isTrue);
    expect(back.players, isEmpty);
    // Kaputte oder fremde Daten führen nicht zum Absturz.
    expect(ScreenState.fromJson('Unsinn').isIdle, isTrue);
    expect(ScreenState.fromJson({'kind': 'gibtsnicht', 'players': 3, 'visit': [1, 'T20']}).visit, ['T20']);
  });

  test('X01-Training: Rest, Checkout-Weg, Aufnahme und Treffer', () {
    final session = GameSession(definition: X01Solo.definition, config: const {'startScore': 170}, seed: 1);
    final darts = [at('T20', 0.0, 0.6), at('T20', 0.01, 0.61)];
    for (final d in darts) {
      session.addDart(d);
    }
    final active = ActiveGame(session: session, playerId: 1, sessionId: 1, revision: 2);
    final s = roundTrip(ScreenSnapshot.training(l10n, active, visit: LiveVisitState(visit: darts), playerName: 'Ben'));

    expect(s.kind, ScreenKind.training);
    expect(s.title, l10n.gameX01);
    expect(s.players.single.name, 'Ben');
    expect(s.players.single.score, '50');
    expect(s.players.single.scoreLabel, l10n.statRemaining);
    expect(s.visit, ['T20', 'T20']);
    expect(s.visitScore, 120);
    expect(s.route, ['BULL']);
    expect(s.hits.map((h) => (h.segment, h.x, h.y)), [('T20', 0.0, 0.6), ('T20', 0.01, 0.61)]);
    expect(s.hitSerial, 2);
    expect(s.finished, isFalse);
  });

  test('X01-Training: letzte Aufnahme nach dem Takeout, Endstand nach Checkout', () {
    final session = GameSession(definition: X01Solo.definition, config: const {'startScore': 101}, seed: 1);
    for (final n in ['T20', 'S1', 'S20']) {
      session.addDart(d(n));
    }
    session.endVisit();
    final waiting = ActiveGame(session: session, playerId: 1, sessionId: 1, revision: 1);
    final s = roundTrip(ScreenSnapshot.training(l10n, waiting, visit: const LiveVisitState()));
    expect(s.visit, isEmpty);
    expect(s.lastVisit, ['T20', 'S1', 'S20']);
    expect(s.lastVisitScore, 81);
    expect(s.players.single.score, '20');
    expect(s.route, ['D10']);

    session.addDart(d('D10'));
    final done = ActiveGame(session: session, playerId: 1, sessionId: 1, revision: 2, ended: true, events: session.game.events.toList());
    final end = roundTrip(ScreenSnapshot.training(l10n, done, visit: LiveVisitState(visit: [d('D10')])));
    expect(end.finished, isTrue);
    expect(end.banner, isNotNull);
    expect(end.bannerTone, ScreenTone.positive);
    expect(end.route, isEmpty);
  });

  test('Around the Clock: Ziel als große Anzeige, Fortschritt und Kennzahlen', () {
    final session = GameSession(definition: AroundTheClock.definition, config: const {}, seed: 3);
    for (final n in ['S1', 'S2', 'MISS']) {
      session.addDart(d(n));
    }
    final active = ActiveGame(session: session, playerId: 1, sessionId: 1, revision: 3, events: session.game.events.toList());
    final s = roundTrip(ScreenSnapshot.training(l10n, active, visit: LiveVisitState(visit: [d('S1'), d('S2'), d('MISS')])));
    expect(s.players.single.scoreLabel, l10n.statTarget);
    expect(s.players.single.score, session.game.display.headline);
    expect(s.progress, session.game.display.progress);
    expect(s.progressLabel, session.game.display.progressLabel);
    expect(s.stats, isNotEmpty);
    expect(s.stats.first.label, isNot(startsWith('stat')));
    expect(s.hits.map((h) => h.x), [null, null, null]);
  });

  test('Match gegen Bot: Tafeln, wer dran ist, Legs und Aufnahme', () {
    const setup = MatchSetup(
      format: MatchFormat(startScore: 301, legsToWin: 2),
      players: [MatchPlayer.human('Ben', profileId: 1), MatchPlayer.bot('CPU 60', average: 60)],
    );
    final session = MatchSession(setup);
    for (final n in ['T20', 'T20', 'T20']) {
      session.addDart(d(n));
    }
    session.endVisit();
    for (final n in ['S20', 'T19']) {
      session.addDart(d(n));
    }
    final state = MatchState(session: session, revision: 3);
    final s = roundTrip(ScreenSnapshot.match(l10n, state));

    expect(s.kind, ScreenKind.match);
    expect(s.title, '301 · ${l10n.gameMatchX01}');
    expect(s.subtitle, contains(l10n.matchLegNumber(1)));
    expect(s.players.map((p) => (p.name, p.score, p.active, p.bot)), [
      ('Ben', '121', false, false),
      ('CPU 60', '224', true, true),
    ]);
    expect(s.players.first.lastVisit, 180);
    expect(s.players.first.average, '180,0');
    expect(s.players.first.legs, 0);
    expect(s.players.first.sets, isNull);
    expect(s.players.first.starter, isTrue);
    expect(s.status, l10n.matchBotThrowing('CPU 60'));
    expect(s.visit, ['S20', 'T19']);
    expect(s.visitScore, 77);
    expect(s.lastVisit, ['T20', 'T20', 'T20']);
    expect(s.lastVisitScore, 180);
  });

  test('Match im Turnier mit Sätzen: Runde im Titel, Bust-Einblendung', () {
    const setup = MatchSetup(
      format: MatchFormat(startScore: 101, legsToWin: 1, setsToWin: 2),
      players: [MatchPlayer.human('Ben'), MatchPlayer.human('Lisa')],
      tournamentMatch: 't1/r2-m0',
    );
    final session = MatchSession(setup);
    for (final n in ['T20', 'S20', 'T19']) {
      session.addDart(d(n));
    }
    final state = MatchState(session: session, revision: 1, events: session.match.events.toList());
    final s = roundTrip(ScreenSnapshot.match(l10n, state, round: l10n.tourRound2));
    expect(s.title, '${l10n.tournamentTitle} · ${l10n.tourRound2}');
    expect(s.players.first.sets, 0);
    expect(s.bust, isTrue);
    expect(s.visitScore, 0);
    expect(s.banner, l10n.matchEvBust('Ben'));
    expect(s.bannerTone, ScreenTone.negative);
  });

  test('Live mit X01: Rest, Legs und Checkout-Weg', () {
    const config = LiveX01Config(startScore: 301);
    final x = LiveX01.replay(config, [
      [Segment.triple(20), Segment.triple(20), Segment.triple(20)],
      [Segment.triple(20), Segment.single(1)],
    ], const []);
    final view = LiveViewState(
      listening: true,
      current: [at('T20', 0, 0.6), at('S1', 0.1, 0.5)],
      lastVisit: [d('T20'), d('T20'), d('T20')],
      stats: LiveStats.of([
        [for (final n in ['T20', 'T20', 'T20']) (segment: Segment.tryParse(n)!, position: null)],
      ]),
      dartSerial: 5,
      x01Config: config,
      x01: x,
    );
    final s = roundTrip(ScreenSnapshot.live(l10n, view, playerName: 'Ben'));
    expect(s.kind, ScreenKind.live);
    expect(s.title, '${l10n.liveTitleX01} · 301');
    expect(s.players.single.score, '60');
    expect(s.players.single.scoreLabel, l10n.statRemaining);
    expect(s.visit, ['T20', 'S1']);
    expect(s.visitScore, 61);
    // Ein Dart übrig: kein Finish auf 60, also der Stell-Vorschlag.
    expect(s.route, [for (final x in x.suggestion ?? const <Segment>[]) x.name]);
    expect(s.setup, [for (final x in x.setup?.darts ?? const <Segment>[]) x.name]);
    expect(s.route.isNotEmpty || s.setupLabel != null, isTrue);
    expect(s.lastVisitScore, 180);
    expect(s.stats.map((e) => e.label), contains(l10n.liveLegs));
    expect(s.hitSerial, 5);
  });

  test('Live ohne X01: Aufnahme als große Zahl, Warten vor dem ersten Dart', () {
    final empty = roundTrip(ScreenSnapshot.live(l10n, const LiveViewState(listening: true)));
    expect(empty.status, l10n.liveWaiting);
    expect(empty.players.single.score, '0');
    expect(empty.players.single.scoreLabel, l10n.statVisitScore);

    final view = LiveViewState(listening: true, current: [d('S20'), d('T5')], stats: LiveStats.of([
      [(segment: Segment.single(20), position: null), (segment: Segment.triple(5), position: null)],
    ]));
    final s = roundTrip(ScreenSnapshot.live(l10n, view));
    expect(s.players.single.score, '35');
    expect(s.status, isNull);
    expect(s.route, isEmpty);
  });
}
