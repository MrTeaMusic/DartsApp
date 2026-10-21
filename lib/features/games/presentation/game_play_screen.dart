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
import '../../../core/router/app_router.dart';
import '../../../core/settings/app_settings.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../board/presentation/double_zoom.dart';
import '../../board/presentation/live_visit_controller.dart';
import '../../caller/presentation/caller_mute_button.dart';
import '../../challenges/presentation/challenge_run_controller.dart';
import '../../challenges/presentation/challenge_widgets.dart';
import '../../dart_source/data/manual_source.dart';
import '../../dart_source/data/simulator_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../matches/presentation/match_texts.dart';
import '../../plans/presentation/plan_run_controller.dart';
import '../../plans/presentation/plan_run_panel.dart';
import '../../profiles/presentation/active_player.dart';
import '../../progress/presentation/celebration_banner.dart';
import '../../stats/domain/tempo_stats.dart';
import '../../stats/presentation/tempo_hint.dart';
import '../../simulator/presentation/manual_keypad.dart';
import '../../simulator/presentation/segment_picker.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../../matches/domain/visit_history.dart';
import '../domain/engine/game_display.dart';
import '../domain/games/x01_solo.dart';
import 'active_game_controller.dart';
import 'game_texts.dart';

/// Spielansicht. Große Zahlen, lesbar aus 2–3 m Abstand.
class GamePlayScreen extends ConsumerWidget {
  const GamePlayScreen({super.key});

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final active = ref.read(activeGameProvider);
    final run = ref.read(challengeRunProvider);
    final challenge = run != null && run.ownsGame(active) ? run : null;
    if (active != null && !active.ended) {
      final l10n = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.gameEndTitle),
          content: Text(l10n.gameEndText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancel)),
            FilledButton(
              key: const Key('confirm-end'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.gameEnd),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    // Vorzeitig verlassen: die Challenge endet ohne Wertung.
    if (challenge != null) ref.read(challengeRunProvider.notifier).clear();
    await ref.read(activeGameProvider.notifier).close();
    if (context.mounted) context.go(challenge != null ? challengeLeaveLocation(challenge) : Routes.games);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final active = ref.watch(activeGameProvider);
    if (active == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton(onPressed: () => context.go(Routes.games), child: Text(l10n.gamesTitle)),
        ),
      );
    }
    final source = ref.watch(dartSourceProvider);
    final live = ref.watch(liveVisitProvider);
    final game = active.game;

    final hits = [for (final d in live.visit) if (d.position != null) d.position!];
    final void Function(BoardPoint, Segment)? onTap = active.ended
        ? null
        : switch (source) {
            SimulatorSource() => (point, _) => source.throwAt(point),
            ManualSource() => (_, segment) => source.enter(segment),
            _ => null,
          };
    final board = DartboardView(
      key: const Key('game-board'),
      hits: hits,
      lastSegment: live.lastDart?.segment,
      hitSerial: live.history.length,
      highlighted: active.ended ? const {} : game.targets,
      onTap: onTap,
    );
    // Nach Bust/Checkout wartet die Aufnahme nur noch auf "Weiter".
    final waiting = active.ended || (game.visitClosed && live.visit.isNotEmpty);
    final zoomTarget = waiting ? null : doubleZoomTarget(route: game.display.suggestion, targets: game.targets);
    DoubleZoomCard zoom({bool compact = false}) => DoubleZoomCard(
          target: zoomTarget,
          hits: hits,
          lastSegment: live.lastDart?.segment,
          hitSerial: live.history.length,
          onTap: onTap,
          compact: compact,
        );

    // Arena (Standard) für X01-Solo: Tafel mit Wurftabelle und Board in der Mitte.
    // Das Arena-Theme gilt für alles darunter, auch für Dialoge und Blätter.
    if (game is X01Solo && ref.watch(settingsProvider.select((s) => s.arenaPlay))) {
      return Theme(
        data: ArenaPalette.theme,
        child: Builder(
          builder: (context) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) unawaited(_leave(context, ref));
            },
            child: Scaffold(
              backgroundColor: ArenaPalette.background,
              body: SafeArea(
                child: CelebrationOverlay(
                  child: _ArenaSoloView(
                    active: active,
                    game: game,
                    board: board,
                    zoom: zoom(compact: true),
                    zoomActive: zoomTarget != null,
                    onLeave: () => _leave(context, ref),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context, ref));
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('leave-game'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _leave(context, ref),
          ),
          title: _gameTitle(context, l10n.gameTitle(active.gameId)),
          actions: [
            SourceStatusBadge(compact: MediaQuery.sizeOf(context).width < 600),
            const SizedBox(width: AppSpacing.xs),
            const CallerMuteButton(),
            // Die breite Arena-Schrift lässt auf dem Telefon keinen Platz dafür.
            if (!(context.look.isArena && MediaQuery.sizeOf(context).width < 600)) const FullscreenButton(),
            const SizedBox(width: AppSpacing.s),
          ],
        ),
        body: SafeArea(
          child: CelebrationOverlay(
            sideWidth: 440,
            child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            // Beim X01 wird das Panel mit der Tabelle hoch: die Knöpfe stehen fest unten
            // (nicht beim Tastenfeld der manuellen Eingabe).
            final pinActions = wide && game is X01Solo && !active.ended && source is! ManualSource;
            final panel = _GamePanel(active: active, large: wide, zoom: zoom(compact: wide && c.maxHeight < 1000 && game is X01Solo), pinActions: pinActions);
            if (wide) {
              return Row(
                children: [
                  Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: board))),
                  SizedBox(
                    width: 440,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, AppSpacing.l, AppSpacing.xl, AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Das Panel scrollt, die Knöpfe bleiben fest am unteren Rand.
                          Expanded(child: SingleChildScrollView(child: panel)),
                          if (pinActions) ...[const SizedBox(height: AppSpacing.m), _GameActions(active: active)],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            // Telefon: Spielstand und Darts oben, damit der Checkout-Weg
            // ohne Scrollen sichtbar ist; darunter das Board.
            final page = context.look.pagePadding(false);
            return ListView(
              padding: EdgeInsets.fromLTRB(page, AppSpacing.s, page, page),
              children: [
                const ChallengeTaskBar(),
                _Headline(active: active, large: false, compact: true),
                const SizedBox(height: AppSpacing.m),
                const ChallengeResultPanel(),
                _EventBanner(active: active),
                _VisitCard(active: active, large: false),
                const SizedBox(height: AppSpacing.m),
                zoom(compact: true),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
                  child: Center(child: board),
                ),
                const SizedBox(height: AppSpacing.m),
                _GamePanel(active: active, large: false, showTop: false),
              ],
            );
          }),
          ),
        ),
      ),
    );
  }
}

/// Tempo der letzten Aufnahmen des laufenden Spiels (nur Darts vom Board).
LiveTempo? _gameTempo(ActiveGame active) =>
    LiveTempo.ofDarts([for (final r in active.session.records) (visit: r.visitIndex, dart: r.dart)]);

/// Arena-Ansicht des X01-Solos: eine Tafel links mit der Wurftabelle, rechts
/// bleibt der Platz leer, in der Mitte Wurfleiste, Schalter und Board.
class _ArenaSoloView extends ConsumerWidget {
  const _ArenaSoloView({
    required this.active,
    required this.game,
    required this.board,
    required this.zoom,
    required this.zoomActive,
    required this.onLeave,
  });
  final ActiveGame active;
  final X01Solo game;
  final Widget board;
  final Widget zoom;
  final bool zoomActive;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final source = ref.watch(dartSourceProvider);
    final live = ref.watch(liveVisitProvider);
    final controller = ref.read(activeGameProvider.notifier);
    final name = ref.watch(activePlayerProvider.select((p) => p?.name)) ?? l10n.arenaPlayerYou;
    final records = active.session.records;
    final thrown = live.visit.length;

    // Aus den Aufzeichnungen abgeleitet: Rückgängig und Korrektur ergeben sich von selbst.
    final rows = VisitHistory.ofSolo(active.session, game).legRowsOf(0);
    final player = ArenaPlayer(
      name: name,
      remaining: game.remaining,
      rows: rows,
      startScore: game.startScore,
      active: !active.ended,
      lastVisit: rows.isEmpty ? 0 : rows.last.points,
      legAverage: formatDecimal(game.legAverage ?? 0),
      matchAverage: formatDecimal(game.average ?? 0),
      legDarts: game.legDarts,
      legs: game.legs > 1 ? game.legsWon : null,
      remainingKey: const Key('solo-remaining'),
      dartsKey: const Key('solo-darts'),
      legsKey: const Key('solo-legs'),
      keyPrefix: 'solo-visits',
    );

    // Nach Bust/Checkout gilt der Weg erst wieder für die nächste Aufnahme.
    final waiting = active.ended || (game.visitClosed && thrown > 0);
    final route = waiting ? null : game.display.suggestion;
    final setup = route == null && !waiting ? game.display.setup : null;
    final plan = route ?? setup?.darts;
    final liveStart = records.length - thrown;

    Future<void> fix(int slot) async {
      final index = liveStart + slot;
      if (index < 0 || index >= records.length) return;
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitle(slot + 1),
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) controller.correct(index, picked);
    }

    final slots = [
      for (var i = 0; i < 3; i++)
        ArenaDartSlot(
          slotKey: Key('dart-slot-$i'),
          segment: i < thrown ? live.visit[i].segment : null,
          planned: plan != null && i >= thrown && i - thrown < plan.length ? plan[i - thrown] : null,
          plannedColor: route != null ? ArenaPalette.hint : colors.setupHint,
          onTap: !active.ended && i < thrown ? () => fix(i) : null,
        ),
    ];

    final bust = waiting && thrown > 0 && ((game.lastDartInfo as X01DartInfo?)?.bust ?? false);
    final event = active.events.isEmpty ? null : active.events.last;
    final tone = event == null ? EventTone.neutral : eventTone(event.type);
    final tempo = tempoHintLine(ref, l10n, _gameTempo(active));
    final messages = ArenaMessages(
      hint: route != null && route.isNotEmpty
          ? '${l10n.visitRoute}: ${route.map((s) => s.name).join(' · ')}'
          : setup != null
          ? l10n.visitSetup(setup.leave)
          : null,
      hintKey: route != null && route.isNotEmpty ? const Key('checkout-route-label') : const Key('setup-route-label'),
      hintColor: route != null ? ArenaPalette.hint : colors.setupHint,
      event: event == null ? null : l10n.eventText(event),
      eventKey: const Key('game-event'),
      eventColor: switch (tone) {
        EventTone.positive => ArenaPalette.success,
        EventTone.negative => ArenaPalette.danger,
        EventTone.neutral => ArenaPalette.blue,
      },
      tempo: tempo,
    );

    final keypad = !active.ended && source is ManualSource ? ManualKeypad(source: source) : null;
    final planRun = ref.watch(planRunProvider);
    final planShown = planRun != null && planRun.stepIndex != null && planRun.sessionId == active.sessionId;
    final header = ChallengeTaskBar.shows(ref) || planShown
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ChallengeTaskBar.shows(ref)) const ChallengeTaskBar(),
              if (planShown) const PlanRunPanel(),
            ],
          )
        : null;

    return ArenaScreen(
      players: [player],
      header: header,
      topBar: (compact, scale) => ArenaTopBar(
        leaveKey: const Key('leave-game'),
        onLeave: onLeave,
        chips: [
          '${game.startScore}',
          l10n.arenaFormatLegs(game.legs),
          inOutCode(doubleIn: game.doubleIn, out: game.outMode),
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
      visitSum: live.visitScore,
      visitBust: bust,
      sumKey: const Key('visit-score'),
      board: board,
      zoom: zoom,
      zoomActive: zoomActive,
      keypad: keypad,
      actions: (height) => ArenaActionBar(
        height: height,
        undoKey: const Key('game-undo'),
        onUndo: controller.undo,
        undoLabel: l10n.boardUndo,
        nextKey: const Key('game-next'),
        onNext: controller.nextVisit,
        nextLabel: l10n.boardNext,
        showUndoNext: keypad == null,
        icons: [
          if (records.isNotEmpty)
            ArenaIconButton(
              key: const Key('open-corrections'),
              icon: Icons.edit_note_rounded,
              tooltip: l10n.fixOpen,
              size: height - 10,
              onPressed: () => showCorrectionsSheet(context),
            ),
          ArenaIconButton(
            key: const Key('end-game'),
            icon: Icons.flag_outlined,
            tooltip: l10n.gameEnd,
            size: height - 10,
            onPressed: controller.end,
          ),
        ],
      ),
      messages: messages,
      messagesExtra: tempo == null ? 0 : 18,
      result: active.ended
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ChallengeResultPanel(),
                  _EventBanner(active: active),
                  _StatsGrid(stats: active.game.result.summary),
                  const SizedBox(height: AppSpacing.m),
                  // Bei einer Challenge stehen die Knöpfe in ihrer Wertung.
                  if (!ChallengeResultPanel.shows(ref)) _ResultActions(active: active),
                ],
              ),
            )
          : null,
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.active, required this.large, this.compact = false});
  final ActiveGame active;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final display = active.game.display;
    // Nach dem Spiel steht die wichtigste Kennzahl oben statt des Spielstands.
    final summary = active.ended ? active.game.result.summary : const <GameStat>[];
    final label = summary.isNotEmpty ? '${l10n.gameResult} · ${l10n.statLabel(summary.first.key)}' : l10n.statLabel(display.headlineKey);
    final headline = summary.isNotEmpty ? summary.first.value : display.headline;
    // Beim X01 steht unter dem Stand, was geworfen wurde: Punkte, Darts und
    // Rest je Aufnahme des laufenden Legs. Die anderen Spiele bleiben wie sie sind.
    final game = active.game;
    // Breit und niedrig (unter 1000 px): kleinere Zahl und 5 Zeilen, damit Aufnahme
    // und Doppel-Zoom möglichst ohne Scrollen auf den Bildschirm passen.
    final short = large && MediaQuery.sizeOf(context).height < 1000;
    final Widget? visits = game is X01Solo
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s),
            child: VisitTable(
              keyPrefix: 'solo-visits',
              rows: VisitHistory.ofSolo(active.session, game).legRowsOf(0),
              startScore: game.startScore,
              maxRows: large ? (short ? 5 : 8) : 6,
              active: !active.ended,
              showDarts: true,
            ),
          )
        : null;
    return ScorePanel(
      label: label,
      footer: visits,
      trailing: display.progressLabel,
      progress: display.progress,
      value: AnimatedSwitcher(
        duration: AppDurations.medium,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
        ),
        child: Text(
          headline,
          key: ValueKey(headline),
          style: ScorePanel.valueStyle(context, hero: large, compact: compact || (short && game is X01Solo)),
        ),
      ),
    );
  }
}

class _GamePanel extends ConsumerWidget {
  const _GamePanel({required this.active, required this.large, this.showTop = true, this.zoom, this.pinActions = false});
  final ActiveGame active;
  final bool large;

  /// Die Knöpfe stehen außerhalb am unteren Rand der Seitenleiste.
  final bool pinActions;

  /// Doppel-Zoom unter den Darts (nur mit [showTop]).
  final Widget? zoom;

  /// Spielstand, Einblendung und Darts; auf dem Telefon stehen sie über dem Board.
  final bool showTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = active.game.display;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTop) ...[
          const ChallengeTaskBar(),
          _Headline(active: active, large: large),
          const SizedBox(height: AppSpacing.m),
          const ChallengeResultPanel(),
          _EventBanner(active: active),
          _VisitCard(active: active, large: large),
          const SizedBox(height: AppSpacing.m),
          ?zoom,
        ],
        _StatsGrid(stats: active.ended ? active.game.result.summary : display.stats),
        const SizedBox(height: AppSpacing.m),
        const PlanRunPanel(),
        if (!pinActions) _GameActions(active: active),
      ],
    );
  }
}

/// Rückgängig, Weiter, Korrigieren und Beenden (bzw. die Ergebnis-Knöpfe).
class _GameActions extends ConsumerWidget {
  const _GameActions({required this.active});
  final ActiveGame active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final source = ref.watch(dartSourceProvider);
    final controller = ref.read(activeGameProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active.ended)
          // Bei einer Challenge stehen die Knöpfe in ihrer Wertung.
          ChallengeResultPanel.shows(ref) ? const SizedBox.shrink() : _ResultActions(active: active)
        else if (source is ManualSource)
          ManualKeypad(source: source)
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('game-undo'),
                  onPressed: controller.undo,
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.boardUndo),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('game-next'),
                  onPressed: controller.nextVisit,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(l10n.boardNext),
                ),
              ),
            ],
          ),
        if (!active.ended) ...[
          const SizedBox(height: AppSpacing.s),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.s,
            children: [
              if (active.session.records.isNotEmpty)
                TextButton.icon(
                  key: const Key('open-corrections'),
                  onPressed: () => showCorrectionsSheet(context),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(l10n.fixOpen),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
                ),
              TextButton.icon(
                key: const Key('end-game'),
                onPressed: controller.end,
                icon: const Icon(Icons.flag_outlined),
                label: Text(l10n.gameEnd),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EventBanner extends StatelessWidget {
  const _EventBanner({required this.active});
  final ActiveGame active;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final event = active.events.isEmpty ? null : active.events.last;
    final color = switch (event == null ? EventTone.neutral : eventTone(event.type)) {
      EventTone.positive => colors.success,
      EventTone.negative => colors.danger,
      EventTone.neutral => theme.colorScheme.primary,
    };
    final Widget banner = event == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            key: ValueKey(active.revision),
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            child: LookBanner(
              text: l10n.eventText(event),
              color: color,
              textKey: const Key('game-event'),
              // Ein Treffer zeigt nur Feld oder Punkte: kleine Beschriftung davor.
              kicker: event.type == GameEventType.hit ? l10n.statHitsOnTarget : null,
            ),
          );
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, child: FadeTransition(opacity: a, child: child)),
      child: banner,
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final List<GameStat> stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final valueStyle = look.statValue.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: (look.statValue.fontSize ?? 30) * (look.id == DartLookId.tv ? 0.72 : 0.75),
    );
    return AppCard(
      child: LayoutBuilder(builder: (context, c) {
        // Drei Spalten; bei vier Werten oder sehr schmal zwei.
        final cols = c.maxWidth < 300 || stats.length == 4 ? 2 : 3;
        final w = (c.maxWidth - (cols - 1) * AppSpacing.m) / cols;
        return Wrap(
          spacing: AppSpacing.m,
          runSpacing: AppSpacing.m + 2,
          children: [
            for (final s in stats)
              SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Kicker(l10n.statLabel(s.key), maxLines: 2),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(s.value, style: valueStyle),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.active});
  final ActiveGame active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('game-done'),
            onPressed: () async {
              await ref.read(activeGameProvider.notifier).close();
              if (context.mounted) context.go(Routes.games);
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.gameDone),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: FilledButton.icon(
            key: const Key('game-again'),
            onPressed: () {
              final config = Map<String, Object?>.of(active.session.config);
              unawaited(ref.read(activeGameProvider.notifier).start(active.session.definition, config));
            },
            icon: const Icon(Icons.replay_rounded),
            label: Text(l10n.gameAgain),
          ),
        ),
      ],
    );
  }
}

/// Die drei Darts der laufenden Aufnahme. Noch offene Plätze zeigen bei
/// Checkout-Spielen den besten Weg in Gelb. Geworfene Darts lassen sich
/// antippen und korrigieren.
class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.active, required this.large});
  final ActiveGame active;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final live = ref.watch(liveVisitProvider);
    final game = active.game;
    final thrown = live.visit.length;
    // Nach Bust/Checkout gilt der Weg erst wieder für die nächste Aufnahme.
    final route = active.ended || (game.visitClosed && thrown > 0) ? null : game.display.suggestion;
    // Geht kein Finish mehr, zeigen wir stattdessen, wie man sich stellt.
    final setup = route == null && !active.ended && !(game.visitClosed && thrown > 0) ? game.display.setup : null;
    final plan = route ?? setup?.darts;
    final planColor = route != null ? colors.highlight : colors.setupHint;
    final records = active.session.records;
    final liveStart = records.length - thrown;

    Future<void> fix(int slot) async {
      final index = liveStart + slot;
      if (index < 0 || index >= records.length) return;
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitle(slot + 1),
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) ref.read(activeGameProvider.notifier).correct(index, picked);
    }

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
                Kicker(l10n.visitLabel),
                const SizedBox(width: AppSpacing.s),
                if (route != null && route.isNotEmpty)
                  Flexible(
                    child: Text(
                      look.caps(l10n.visitRoute),
                      key: const Key('checkout-route-label'),
                      overflow: TextOverflow.ellipsis,
                      style: look.kicker.copyWith(color: colors.highlight),
                    ),
                  )
                else if (setup != null)
                  Flexible(
                    child: Text(
                      look.caps(l10n.visitSetup(setup.leave)),
                      key: const Key('setup-route-label'),
                      overflow: TextOverflow.ellipsis,
                      style: look.kicker.copyWith(color: colors.setupHint),
                    ),
                  )
                else if (route != null && thrown == 0)
                  Flexible(
                    child: Text(l10n.gameNoCheckout, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ),
                const Spacer(),
                Text(
                  '${live.visitScore}',
                  key: const Key('visit-score'),
                  style: look.chipNumber.copyWith(color: theme.colorScheme.onSurface, fontSize: (look.chipNumber.fontSize ?? 18) + 4),
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
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: FittedBox(
                      child: DartChip(
                        key: Key('dart-slot-$i'),
                        segment: i < thrown ? live.visit[i].segment : null,
                        planned: plan != null && i >= thrown && i - thrown < plan.length ? plan[i - thrown] : null,
                        plannedColor: planColor,
                        label: '${i + 1}',
                        large: true,
                        onTap: !active.ended && i < thrown ? () => fix(i) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          TempoHint(tempo: _gameTempo(active)),
        ],
      ),
    );
  }
}

/// Liste der Aufnahmen dieses Spiels; jeder Dart lässt sich korrigieren.
Future<void> showCorrectionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => const _CorrectionsSheet(),
  );
}

class _CorrectionsSheet extends ConsumerWidget {
  const _CorrectionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final active = ref.watch(activeGameProvider);
    if (active == null) return const SizedBox.shrink();
    final records = active.session.records;
    final visits = <int, List<int>>{};
    for (var i = 0; i < records.length; i++) {
      visits.putIfAbsent(records[i].visitIndex, () => []).add(i);
    }
    final order = visits.keys.toList()..sort((a, b) => b.compareTo(a));

    Future<void> fix(int index) async {
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitleAny,
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) ref.read(activeGameProvider.notifier).correct(index, picked);
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
              child: Text(l10n.fixHint, style: theme.textTheme.bodySmall),
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
                            width: 72,
                            child: Text(l10n.fixVisit(v + 1), style: theme.textTheme.labelMedium),
                          ),
                          for (final i in visits[v]!)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.s),
                              child: Opacity(
                                opacity: records[i].counted ? 1 : 0.45,
                                child: DartChip(
                                  key: Key('fix-dart-$i'),
                                  segment: records[i].dart.segment,
                                  onTap: () => fix(i),
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '${visits[v]!.where((i) => records[i].counted).fold<int>(0, (s, i) => s + records[i].dart.score)}',
                            style: context.look.chipNumber.copyWith(color: theme.colorScheme.onSurface),
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

/// Titel der Spielansicht. In der Arena-Schrift ist der Titel auf dem Telefon
/// zu breit für die Leiste: er schrumpft dann, statt abgeschnitten zu werden.
Widget _gameTitle(BuildContext context, String title) {
  final narrow = MediaQuery.sizeOf(context).width < 600;
  final text = Text(
    title,
    maxLines: 1,
    style: narrow ? Theme.of(context).textTheme.titleLarge : null,
  );
  if (narrow && context.look.isArena) {
    return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: text);
  }
  return text;
}
