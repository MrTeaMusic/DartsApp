import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/arena/arena_chrome.dart';
import '../../../core/design/arena/arena_palette.dart';
import '../../../core/design/arena/arena_player_panel.dart';
import '../../../core/design/arena/arena_screen.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../caller/presentation/caller_mute_button.dart';
import '../../challenges/presentation/challenge_run_controller.dart';
import '../../challenges/presentation/challenge_widgets.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../board/presentation/double_zoom.dart';
import '../../dart_source/data/manual_source.dart';
import '../../dart_source/data/simulator_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../progress/presentation/celebration_banner.dart';
import '../../games/domain/engine/game_display.dart';
import '../../simulator/presentation/manual_keypad.dart';
import '../../simulator/presentation/segment_picker.dart';
import '../domain/match_session.dart';
import '../domain/visit_history.dart';
import '../domain/x01_match.dart';
import 'match_controller.dart';
import 'match_routes.dart';
import 'match_texts.dart';

/// Restpunkte und Endstand: kleiner als die große Zahl im Training, weil
/// zwei Tafeln nebeneinander stehen und das Ergebnis darunter Platz braucht.
TextStyle _matchScore(BuildContext context) {
  final style = ScorePanel.valueStyle(context, hero: false);
  return style.copyWith(fontSize: (style.fontSize ?? 96) * 0.6);
}

/// Spielansicht eines Matches: Anzeigetafel je Spieler, Board mit den Darts
/// der laufenden Aufnahme (auch denen des Bots) und die Aufnahme-Karte.
class MatchPlayScreen extends ConsumerWidget {
  const MatchPlayScreen({super.key});

  static Future<void> leave(BuildContext context, WidgetRef ref) async {
    final state = ref.read(matchControllerProvider);
    final inTournament = state?.setup.tournamentMatch != null;
    final run = ref.read(challengeRunProvider);
    final challenge = run != null && run.ownsMatch(state) ? run : null;
    if (state != null && !state.ended) {
      final l10n = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(inTournament ? l10n.matchPauseTitle : l10n.matchLeaveTitle),
          content: Text(inTournament ? l10n.matchPauseText : l10n.matchLeaveText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.matchStay)),
            FilledButton(
              key: const Key('confirm-leave-match'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(inTournament ? l10n.matchPause : l10n.matchLeave),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    // Vorzeitig verlassen: die Challenge endet ohne Wertung.
    if (challenge != null) ref.read(challengeRunProvider.notifier).clear();
    await ref.read(matchControllerProvider.notifier).close(keepForResume: inTournament);
    if (!context.mounted) return;
    if (challenge != null) {
      context.go(challengeLeaveLocation(challenge));
    } else {
      context.go(inTournament ? MatchRoutes.tournament : MatchRoutes.hub);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(matchControllerProvider);
    if (state == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton(onPressed: () => context.go(MatchRoutes.hub), child: Text(l10n.matchesTitle)),
        ),
      );
    }
    final source = ref.watch(dartSourceProvider);
    final match = state.match;
    final visit = [for (final i in state.session.currentVisitIndexes) state.session.records[i]];
    final route = state.humanTurn && !match.visitClosed ? match.suggestion : null;

    final hits = [for (final r in visit) ?r.dart.position];
    final lastSegment = visit.isEmpty ? null : visit.last.dart.segment;
    final void Function(BoardPoint, Segment)? onTap = !state.acceptsHumanDarts
        ? null
        : switch (source) {
            SimulatorSource() => (point, _) => source.throwAt(point),
            ManualSource() => (_, segment) => source.enter(segment),
            _ => null,
          };
    final board = DartboardView(
      key: const Key('match-board'),
      hits: hits,
      lastSegment: lastSegment,
      hitSerial: state.session.records.length,
      highlighted: route == null || route.isEmpty ? const {} : {route.first},
      onTap: onTap,
    );
    // Breit stehen die Knöpfe fest unten, außer beim Tastenfeld der manuellen Eingabe.
    final pinActions = !state.ended && !(state.acceptsHumanDarts && source is ManualSource);
    final zoomTarget = route == null || state.ended ? null : doubleZoomTarget(route: route);
    DoubleZoomCard zoom({bool compact = false}) => DoubleZoomCard(
          target: zoomTarget,
          hits: hits,
          lastSegment: lastSegment,
          hitSerial: state.session.records.length,
          onTap: onTap,
          compact: compact,
        );

    final format = state.setup.format;
    final legLabel = format.usesSets
        ? l10n.matchLegSetNumber(match.setNumber, match.legNumber)
        : l10n.matchLegNumber(match.legNumber);

    // Arena: drei Spalten mit großen Tafeln und Wurftabelle (Standard).
    if (ref.watch(settingsProvider.select((s) => s.playView)) == PlayView.arena) {
      return _SaveOnBackground(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(leave(context, ref));
          },
          child: Scaffold(
            backgroundColor: ArenaPalette.background,
            body: SafeArea(
              child: CelebrationOverlay(
                child: _ArenaMatchView(
                  state: state,
                  route: route,
                  board: board,
                  zoom: zoom(compact: true),
                  zoomActive: zoomTarget != null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _SaveOnBackground(
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave(context, ref));
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('leave-match'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => leave(context, ref),
          ),
          title: Text(state.ended ? l10n.matchResultTitle : legLabel),
          actions: [
            SourceStatusBadge(compact: MediaQuery.sizeOf(context).width < 600),
            const SizedBox(width: AppSpacing.xs),
            const CallerMuteButton(),
            const FullscreenButton(),
            const SizedBox(width: AppSpacing.s),
          ],
        ),
        body: SafeArea(
          child: CelebrationOverlay(
            sideWidth: 500,
            child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              if (wide) {
                return Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: board),
                      ),
                    ),
                    SizedBox(
                      width: 500,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, AppSpacing.l, AppSpacing.xl, AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              // Mit den Aufnahmen-Tabellen wird das Panel hoch: es scrollt, die Knöpfe
                              // darunter bleiben fest am unteren Rand.
                              child: SingleChildScrollView(
                                child: _Panel(
                                  state: state,
                                  route: route,
                                  zoom: zoom(compact: c.maxHeight < 1000),
                                  wide: true,
                                  pinActions: pinActions,
                                ),
                              ),
                            ),
                            if (pinActions) ...[const SizedBox(height: AppSpacing.m), _MatchActions(state: state)],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              // Telefon: Tafel, Einblendung und Darts oben, darunter das Board.
              final page = context.look.pagePadding(false);
              return ListView(
                padding: EdgeInsets.fromLTRB(page, AppSpacing.s, page, page),
                children: [
                  const ChallengeTaskBar(),
                  _Scoreboard(state: state, route: route),
                  const SizedBox(height: AppSpacing.m),
                  if (state.ended)
                    _Panel(state: state, route: route, showScoreboard: false)
                  else ...[
                    _EventBanner(state: state),
                    _VisitCard(state: state, route: route),
                    const SizedBox(height: AppSpacing.m),
                    zoom(compact: true),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: c.maxHeight * 0.42),
                      child: Center(child: board),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    _Panel(state: state, route: route, showScoreboard: false, showVisit: false),
                  ],
                ],
              );
            },
          ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Arena-Ansicht des Matches: Tafeln mit Wurftabelle links und rechts, in der
/// Mitte Wurfleiste, Schalter und Board.
class _ArenaMatchView extends ConsumerWidget {
  const _ArenaMatchView({
    required this.state,
    required this.route,
    required this.board,
    required this.zoom,
    required this.zoomActive,
  });
  final MatchState state;
  final List<Segment>? route;
  final Widget board;
  final Widget zoom;
  final bool zoomActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final source = ref.watch(dartSourceProvider);
    final controller = ref.read(matchControllerProvider.notifier);
    final match = state.match;
    final session = state.session;
    final format = state.setup.format;
    final setupPlayers = state.setup.players;
    // Eine Ableitung aus den Aufzeichnungen für alle Tafeln; Rückgängig und
    // Korrektur ergeben sich von selbst.
    final history = VisitHistory.ofMatch(session);

    final players = [
      for (var i = 0; i < setupPlayers.length; i++)
        ArenaPlayer(
          name: setupPlayers[i].name,
          isBot: setupPlayers[i].isBot,
          remaining: match.players[i].remaining,
          rows: history.legRowsOf(i),
          startScore: format.startScore,
          active: !state.ended && match.current == i,
          won: match.winner == i,
          starter: !state.ended && match.legStarter == i,
          lastVisit: match.players[i].lastVisit ?? 0,
          legAverage: formatDecimal(match.players[i].legAverage ?? 0),
          matchAverage: formatDecimal(match.players[i].average ?? 0),
          legDarts: match.players[i].legDartPoints.length,
          legs: format.usesSets ? match.players[i].legs : match.players[i].totalLegs,
          sets: format.usesSets ? match.players[i].sets : null,
          panelKey: Key('match-active-$i-${!state.ended && match.current == i}'),
          remainingKey: Key('match-remaining-$i'),
          dartsKey: Key('match-darts-$i'),
          legsKey: Key('match-legs-$i'),
          setsKey: Key('match-sets-$i'),
          keyPrefix: 'match-visits-$i',
        ),
    ];

    // Die Darts der laufenden Aufnahme; offene Plätze zeigen den Weg.
    final indexes = session.currentVisitIndexes;
    final thrown = indexes.length;
    final current = setupPlayers[match.current];
    final next = setupPlayers[match.nextPlayer];
    final colors = context.dartColors;
    final plan = route ?? (route == null && state.humanTurn && !match.visitClosed ? match.setup?.darts : null);

    Future<void> fix(int slot) async {
      final index = indexes[slot];
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitle(slot + 1),
        subtitle: l10n.fixCurrent(session.records[index].dart.segment.name),
      );
      if (picked != null) controller.correct(index, picked);
    }

    final slots = [
      for (var i = 0; i < 3; i++)
        ArenaDartSlot(
          slotKey: Key('match-dart-$i'),
          segment: i < thrown ? session.records[indexes[i]].dart.segment : null,
          planned: plan != null && i >= thrown && i - thrown < plan.length ? plan[i - thrown] : null,
          plannedColor: route != null ? ArenaPalette.hint : colors.setupHint,
          onTap: i < thrown && !current.isBot && !state.ended ? () => fix(i) : null,
        ),
    ];

    // Meldungen unter dem Board: Weg, Status, Ereignis.
    final soloHuman = setupPlayers.where((p) => !p.isBot).length == 1;
    final status = match.visitClosed && match.nextPlayer != match.current
        ? (soloHuman && !next.isBot ? l10n.matchWaitTakeoutYou : l10n.matchWaitTakeout(next.name))
        : current.isBot
        ? l10n.matchBotThrowing(current.name)
        : soloHuman
        ? l10n.matchYourTurn
        : l10n.matchTurnOf(current.name);
    final setup = route == null && state.humanTurn && !match.visitClosed ? match.setup : null;
    final event = _bannerEvent(state);
    final names = [for (final p in setupPlayers) p.name];
    final messages = ArenaMessages(
      hint: route != null && route!.isNotEmpty
          ? '${l10n.visitRoute}: ${route!.map((s) => s.name).join(' · ')}'
          : setup != null
          ? l10n.visitSetup(setup.leave)
          : null,
      hintKey: route != null && route!.isNotEmpty ? Key('match-route-${match.current}') : Key('match-setup-${match.current}'),
      hintColor: route != null ? ArenaPalette.hint : colors.setupHint,
      status: state.ended ? null : status,
      statusKey: const Key('match-status'),
      statusMuted: current.isBot,
      event: event == null ? null : l10n.matchEventText(event, names),
      eventKey: const Key('match-event'),
      eventColor: event?.type == MatchEventType.bust ? ArenaPalette.danger : ArenaPalette.success,
    );

    final keypad = !state.ended && state.acceptsHumanDarts && source is ManualSource ? ManualKeypad(source: source) : null;

    return ArenaScreen(
      players: players,
      header: ChallengeTaskBar.shows(ref) ? const ChallengeTaskBar() : null,
      topBar: (compact, scale) => ArenaTopBar(
        leaveKey: const Key('leave-match'),
        onLeave: () => MatchPlayScreen.leave(context, ref),
        chips: [
          '${format.startScore}',
          format.usesSets ? l10n.arenaFormatSets(format.setsToWin, format.legsToWin) : l10n.arenaFormatLegs(format.legsToWin),
          inOutCode(doubleIn: format.doubleIn, out: format.outMode),
        ],
        trailing: [
          SourceStatusBadge(compact: MediaQuery.sizeOf(context).width < 900),
          const SizedBox(width: AppSpacing.xs),
          const CallerMuteButton(),
          const FullscreenButton(),
        ],
        compact: compact,
        scale: scale,
      ),
      dartSlots: slots,
      visitSum: match.visitScore,
      visitBust: match.visitBust,
      sumKey: const Key('match-visit-score'),
      board: board,
      zoom: zoom,
      zoomActive: zoomActive,
      keypad: keypad,
      actions: (height) => ArenaActionBar(
        height: height,
        undoKey: const Key('match-undo'),
        onUndo: state.session.canUndo ? controller.undo : null,
        undoLabel: l10n.boardUndo,
        nextKey: const Key('match-next'),
        onNext: state.humanTurn && match.physicalDartsInVisit > 0 ? controller.nextVisit : null,
        nextLabel: l10n.boardNext,
        showUndoNext: keypad == null,
        icons: [
          ArenaIconButton(
            key: const Key('match-corrections'),
            icon: Icons.edit_note_rounded,
            tooltip: l10n.fixOpen,
            size: height - 10,
            onPressed: () => _showCorrections(context),
          ),
        ],
      ),
      messages: messages,
      result: state.ended
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EventBanner(state: state),
                  // Bei einer Challenge ersetzt ihre Wertung die Knöpfe.
                  if (ChallengeResultPanel.shows(ref)) const ChallengeResultPanel(),
                  _ResultCard(state: state),
                  const SizedBox(height: AppSpacing.m),
                  if (!ChallengeResultPanel.shows(ref)) _ResultActions(state: state),
                ],
              ),
            )
          : null,
    );
  }
}

/// Sichert das laufende Match zum Fortsetzen, wenn die App in den
/// Hintergrund geht oder beendet wird (sonst nur am Aufnahme-Ende).
class _SaveOnBackground extends ConsumerStatefulWidget {
  const _SaveOnBackground({required this.child});
  final Widget child;

  @override
  ConsumerState<_SaveOnBackground> createState() => _SaveOnBackgroundState();
}

class _SaveOnBackgroundState extends ConsumerState<_SaveOnBackground> {
  late final AppLifecycleListener _lifecycle;

  void _save() => ref.read(matchControllerProvider.notifier).saveProgress();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _save, onPause: _save, onDetach: _save);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Panel extends ConsumerWidget {
  const _Panel({
    required this.state,
    required this.route,
    this.showScoreboard = true,
    this.showVisit = true,
    this.zoom,
    this.wide = false,
    this.pinActions = false,
  });
  final MatchState state;
  final List<Segment>? route;
  final bool showScoreboard;

  /// Rückgängig, Weiter und Korrigieren stehen außerhalb (am unteren Rand der
  /// Seitenleiste), damit sie ohne Scrollen erreichbar bleiben.
  final bool pinActions;

  /// Breites Layout: Anzeigetafel mit längeren Aufnahmen-Tabellen.
  final bool wide;

  /// Doppel-Zoom unter der Aufnahme (nur mit [showVisit]).
  final Widget? zoom;

  /// Einblendung und Aufnahme; auf dem Telefon stehen sie über dem Board.
  final bool showVisit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(dartSourceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showScoreboard) ...[
          const ChallengeTaskBar(),
          _Scoreboard(state: state, route: route, wide: wide),
          const SizedBox(height: AppSpacing.m),
        ],
        if (showVisit || state.ended) _EventBanner(state: state),
        if (state.ended) ...[
          // Bei einer Challenge ersetzt ihre Wertung die Knöpfe.
          if (ChallengeResultPanel.shows(ref)) const ChallengeResultPanel(),
          _ResultCard(state: state),
          const SizedBox(height: AppSpacing.m),
          if (!ChallengeResultPanel.shows(ref)) _ResultActions(state: state),
        ] else ...[
          if (showVisit) ...[_VisitCard(state: state, route: route), const SizedBox(height: AppSpacing.m), ?zoom],
          if (state.acceptsHumanDarts && source is ManualSource) ...[
            ManualKeypad(source: source),
            const SizedBox(height: AppSpacing.s),
            _MatchActions(state: state, correctionsOnly: true),
          ] else if (!pinActions)
            _MatchActions(state: state),
        ],
      ],
    );
  }
}

/// Rückgängig, Weiter und Korrigieren unter dem Panel.
class _MatchActions extends ConsumerWidget {
  const _MatchActions({required this.state, this.correctionsOnly = false});
  final MatchState state;

  /// Nur „Korrigieren“ (beim Tastenfeld der manuellen Eingabe).
  final bool correctionsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(matchControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!correctionsOnly) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('match-undo'),
                  onPressed: state.session.canUndo ? controller.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.boardUndo),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('match-next'),
                  onPressed: state.humanTurn && state.match.physicalDartsInVisit > 0 ? controller.nextVisit : null,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(l10n.boardNext),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        Center(
          child: TextButton.icon(
            key: const Key('match-corrections'),
            onPressed: () => _showCorrections(context),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(l10n.fixOpen),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Anzeigetafel: eine Karte je Spieler, darin Stand, Kennzahlen und die
/// Tabelle der letzten Aufnahmen im laufenden Leg.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.state, required this.route, this.wide = false});
  final MatchState state;
  final List<Segment>? route;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final players = state.setup.players;
    // Eine Ableitung aus den Aufzeichnungen für alle Karten (billig: ein
    // Durchlauf über die Darts; Rückgängig und Korrektur ergeben sich von selbst).
    final history = VisitHistory.ofMatch(state.session);
    final many = players.length >= 3;
    // Breit und niedrig (unter 1000 px) bleibt Platz für Aufnahme und Doppel-Zoom: 5 Zeilen.
    final short = MediaQuery.sizeOf(context).height < 1000;
    final maxRows = wide ? (short ? 5 : (many ? 6 : 7)) : (many ? 4 : 5);
    // Breit steht nach dem Match die Ergebnis-Karte im selben Panel: die Tabellen
    // entfallen dort, damit die Knöpfe ohne Scrollen sichtbar bleiben.
    final showTable = !(wide && state.ended);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < players.length; i++) ...[
            if (i > 0) SizedBox(width: context.look.gridGap),
            Expanded(
              child: _PlayerCard(
                state: state,
                index: i,
                route: i == state.match.current ? route : null,
                visits: history.legRowsOf(i),
                maxRows: maxRows,
                showTable: showTable,
                compact: !wide,
                dense: many && !wide,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.state,
    required this.index,
    required this.route,
    required this.visits,
    required this.maxRows,
    required this.showTable,
    required this.compact,
    required this.dense,
  });
  final MatchState state;
  final int index;
  final List<Segment>? route;

  /// Aufnahmen des Spielers im laufenden Leg, die älteste zuerst.
  final List<VisitRow> visits;
  final int maxRows;
  final bool showTable;

  /// Schmale Karte (Telefon): engere Abstände, Kennzahlen in einer Zeile.
  final bool compact;

  /// Sehr schmale Karte (drei oder mehr Spieler auf dem Telefon): Kennzahlen
  /// als Zeilen, Tabelle ohne „Bust“-Beschriftung.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final match = state.match;
    final player = state.setup.players[index];
    final p = match.players[index];
    final active = !state.ended && match.current == index;
    final won = match.winner == index;
    final accent = won ? colors.success : theme.colorScheme.primary;
    final format = state.setup.format;
    final starter = !state.ended && match.legStarter == index;

    final look = context.look;
    final lit = active || won;
    // Geht kein Finish mehr, steht hier, wie man sich stellt.
    final setup = route == null && state.humanTurn && match.current == index && !match.visitClosed ? match.setup : null;
    final valueStyle = look.chipNumber.copyWith(fontSize: 16, color: theme.colorScheme.onSurface);
    Widget stat(String label, String value, {Key? key}) => dense
        ? Row(
            children: [
              Expanded(child: Kicker(label)),
              Text(value, key: key, style: valueStyle.copyWith(fontSize: 14)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Kicker(label),
              Text(value, key: key, style: valueStyle),
            ],
          );
    final stats = [
      if (format.usesSets) stat(l10n.matchSets, '${p.sets}', key: Key('match-sets-$index')),
      stat(l10n.matchLegs, '${format.usesSets ? p.legs : p.totalLegs}', key: Key('match-legs-$index')),
      stat(l10n.matchAvg, formatDecimal(p.average)),
      stat(l10n.matchDarts, '${p.darts}', key: Key('match-darts-$index')),
    ];

    return KeyedSubtree(
      // Markierung, wer am Zug ist (bzw. gewonnen hat).
      key: Key('match-active-$index-$active'),
      child: ScorePanel(
        label: player.name,
        active: lit,
        compact: compact,
        pinFooter: true,
        badge: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (starter) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: colors.highlight, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            if (won) ...[
              Icon(Icons.emoji_events_rounded, size: 16, color: colors.success),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(
              player.isBot ? Icons.smart_toy_outlined : Icons.person_rounded,
              size: 16,
              color: lit ? (look.id == DartLookId.tv ? theme.colorScheme.onSurface : accent) : colors.textMuted,
            ),
          ],
        ),
        value: Text(
          '${p.remaining}',
          key: Key('match-remaining-$index'),
          // Einzeilig, sonst misst IntrinsicHeight eine umbrochene Zahl und die Karten werden zu hoch.
          softWrap: false,
          maxLines: 1,
          style: _matchScore(context)
              .copyWith(color: lit ? theme.colorScheme.onSurface : colors.textMuted),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 20,
              child: route != null && route!.isNotEmpty
                  ? Text(
                      look.caps(route!.map((s) => s.name).join(' · ')),
                      key: Key('match-route-$index'),
                      overflow: TextOverflow.ellipsis,
                      style: look.chipNumber.copyWith(fontSize: 15, color: colors.highlight),
                    )
                  : setup != null
                  ? Text(
                      look.caps(l10n.visitSetup(setup.leave)),
                      key: Key('match-setup-$index'),
                      overflow: TextOverflow.ellipsis,
                      style: look.chipNumber.copyWith(fontSize: 15, color: colors.setupHint),
                    )
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (dense)
              Column(mainAxisSize: MainAxisSize.min, children: stats)
            else if (compact)
              // Eine Zeile; bei vier Kennzahlen (Satzmodus) rücken sie enger.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in stats)
                    Expanded(
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: w),
                    ),
                ],
              )
            else
              Wrap(spacing: AppSpacing.l, runSpacing: AppSpacing.s, children: stats),
            if (showTable) ...[
              SizedBox(height: compact ? AppSpacing.s : AppSpacing.m),
              VisitTable(
                keyPrefix: 'match-visits-$index',
                rows: visits,
                startScore: format.startScore,
                maxRows: maxRows,
                active: lit,
                dense: dense,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _bannerPriority = [
  MatchEventType.matchWon,
  MatchEventType.setWon,
  MatchEventType.legWon,
  MatchEventType.bust,
  MatchEventType.max,
];

/// Das wichtigste Ereignis der laufenden Aufnahme für die Einblendung.
MatchEvent? _bannerEvent(MatchState state) {
  MatchEvent? event;
  for (final t in _bannerPriority) {
    event ??= state.events.where((e) => e.type == t).firstOrNull;
  }
  return event;
}

class _EventBanner extends StatelessWidget {
  const _EventBanner({required this.state});
  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final event = _bannerEvent(state);
    final color = switch (event?.type) {
      MatchEventType.bust => colors.danger,
      null => Theme.of(context).colorScheme.primary,
      _ => colors.success,
    };
    final names = [for (final p in state.setup.players) p.name];
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      transitionBuilder: (child, a) => SizeTransition(
        sizeFactor: a,
        child: FadeTransition(opacity: a, child: child),
      ),
      child: event == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(state.revision),
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: LookBanner(text: l10n.matchEventText(event, names), color: color, textKey: const Key('match-event')),
            ),
    );
  }
}

/// Die Darts der laufenden Aufnahme. Bei Menschen zeigen offene Plätze den
/// Checkout-Weg in Gelb, geworfene Darts lassen sich antippen und korrigieren.
class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.state, required this.route});
  final MatchState state;
  final List<Segment>? route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final match = state.match;
    final session = state.session;
    final indexes = session.currentVisitIndexes;
    final thrown = indexes.length;
    final player = state.setup.players[match.current];
    final next = state.setup.players[match.nextPlayer];
    // Gegen CPUs gibt es genau einen Menschen: den sprechen wir direkt an.
    final soloHuman = state.setup.players.where((p) => !p.isBot).length == 1;
    final status = match.visitClosed && match.nextPlayer != match.current
        ? (soloHuman && !next.isBot ? l10n.matchWaitTakeoutYou : l10n.matchWaitTakeout(next.name))
        : player.isBot
        ? l10n.matchBotThrowing(player.name)
        : soloHuman
        ? l10n.matchYourTurn
        : l10n.matchTurnOf(player.name);

    Future<void> fix(int slot) async {
      final index = indexes[slot];
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitle(slot + 1),
        subtitle: l10n.fixCurrent(session.records[index].dart.segment.name),
      );
      if (picked != null) ref.read(matchControllerProvider.notifier).correct(index, picked);
    }

    final setup = route == null && state.humanTurn && !match.visitClosed ? match.setup : null;
    final r = route ?? setup?.darts;
    final planColor = route != null ? colors.highlight : colors.setupHint;
    final look = context.look;
    return AppCard(
      padding: EdgeInsets.all(look.id == DartLookId.clean ? AppSpacing.l : AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    key: const Key('match-status'),
                    overflow: TextOverflow.ellipsis,
                    style: (look.id == DartLookId.clean ? theme.textTheme.titleSmall : look.kicker)?.copyWith(
                      color: player.isBot ? colors.textMuted : theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  match.visitBust ? 'BUST' : '${match.visitScore}',
                  key: const Key('match-visit-score'),
                  style: look.chipNumber.copyWith(
                    fontSize: (look.chipNumber.fontSize ?? 18) + 4,
                    color: match.visitBust ? colors.danger : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: look.id == DartLookId.clean ? AppSpacing.m : AppSpacing.s),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    child: FittedBox(
                      child: DartChip(
                        key: Key('match-dart-$i'),
                        segment: i < thrown ? session.records[indexes[i]].dart.segment : null,
                        planned: r != null && i >= thrown && i - thrown < r.length ? r[i - thrown] : null,
                        plannedColor: planColor,
                        label: '${i + 1}',
                        large: true,
                        onTap: i < thrown && !player.isBot ? () => fix(i) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state});
  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final match = state.match;
    final players = state.setup.players;
    final format = state.setup.format;
    final ps = match.players;
    final score = format.usesSets ? ps.map((p) => p.sets).join(' : ') : ps.map((p) => p.totalLegs).join(' : ');

    final rows = <(String, List<String>)>[
      if (format.usesSets) (l10n.matchStatSets, [for (final p in ps) '${p.sets}']),
      (l10n.matchStatLegs, [for (final p in ps) '${p.totalLegs}']),
      (l10n.matchStatAverage, [for (final p in ps) formatDecimal(p.average)]),
      (l10n.matchStatFirst9, [for (final p in ps) formatDecimal(p.first9Average)]),
      (l10n.matchStatCheckout, [for (final p in ps) formatPercent(p.checkoutRate)]),
      (l10n.matchStatHighFinish, [for (final p in ps) p.highestFinish == 0 ? '–' : '${p.highestFinish}']),
      (l10n.matchStatBestLeg, [for (final p in ps) p.bestLegDarts == null ? '–' : '${p.bestLegDarts}']),
      (l10n.matchStatScores, [for (final p in ps) '${p.count100} / ${p.count140} / ${p.count180}']),
      (l10n.matchStatDarts, [for (final p in ps) '${p.darts}']),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(l10n.matchResultTitle),
          const SizedBox(height: AppSpacing.s),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              score,
              key: const Key('match-final-score'),
              style: _matchScore(context).copyWith(color: colors.success),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (var i = 0; i < players.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: Text(
                        players[i].name,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: match.winner == i ? colors.success : null),
                      ),
                    ),
                ],
              ),
              for (final (label, values) in rows)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                    for (final v in values)
                      Text(
                        v,
                        textAlign: TextAlign.end,
                        style: context.look.chipNumber.copyWith(fontSize: 15, color: theme.colorScheme.onSurface),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.state});
  final MatchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final inTournament = state.setup.tournamentMatch != null;
    final controller = ref.read(matchControllerProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('match-done'),
            onPressed: () async {
              await controller.close();
              if (context.mounted) context.go(inTournament ? MatchRoutes.tournament : MatchRoutes.hub);
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.matchDone),
          ),
        ),
        if (inTournament) ...[
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: FilledButton.icon(
              key: const Key('match-to-tournament'),
              onPressed: () async {
                await controller.close();
                if (context.mounted) context.go(MatchRoutes.tournament);
              },
              icon: const Icon(Icons.account_tree_rounded),
              label: Text(l10n.matchBackToTournament),
            ),
          ),
        ] else ...[
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: FilledButton.icon(
              key: const Key('match-rematch'),
              onPressed: () {
                final s = state.setup;
                // Revanche: der andere fängt an.
                final rematch = MatchSetup(
                  format: s.format,
                  players: s.players,
                  firstStarter: (s.firstStarter + 1) % s.players.length,
                );
                unawaited(controller.start(rematch));
              },
              icon: const Icon(Icons.replay_rounded),
              label: Text(l10n.matchRematch),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _showCorrections(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (context) => const _CorrectionsSheet(),
);

/// Eigene Darts im laufenden Leg, je Aufnahme; jeder lässt sich korrigieren.
class _CorrectionsSheet extends ConsumerWidget {
  const _CorrectionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(matchControllerProvider);
    if (state == null) return const SizedBox.shrink();
    final records = state.session.records;
    final leg = state.match.legNumber;
    final visits = <int, List<int>>{};
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      if (r.leg != leg || state.setup.players[r.player].isBot) continue;
      visits.putIfAbsent(r.visitSerial, () => []).add(i);
    }
    final order = visits.keys.toList()..sort((a, b) => b.compareTo(a));

    Future<void> fix(int index) async {
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitleAny,
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) ref.read(matchControllerProvider.notifier).correct(index, picked);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xs),
              child: Text(l10n.fixOpen, style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.m),
              child: Text(
                order.isEmpty ? l10n.matchNoCorrections : l10n.matchCorrectHint,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.l),
                children: [
                  for (final v in order)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              state.setup.players[records[visits[v]!.first].player].name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                          for (final i in visits[v]!)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.s),
                              child: Opacity(
                                opacity: records[i].counted ? 1 : 0.45,
                                child: DartChip(
                                  key: Key('match-fix-$i'),
                                  segment: records[i].dart.segment,
                                  onTap: () => fix(i),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
