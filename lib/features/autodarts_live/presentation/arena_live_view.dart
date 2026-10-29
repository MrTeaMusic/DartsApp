import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dart_source/presentation/board_help.dart';
import '../../board/presentation/board_status_frame.dart';
import '../../../core/design/arena/arena_chrome.dart';
import '../../../core/design/arena/arena_palette.dart';
import '../../../core/design/arena/arena_player_panel.dart';
import '../../../core/design/arena/arena_screen.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../dart_source/domain/dart_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../games/domain/engine/game_display.dart';
import '../../matches/domain/visit_history.dart';
import '../../matches/presentation/match_texts.dart';
import '../../profiles/presentation/active_player.dart';
import '../../stats/domain/tempo_stats.dart';
import '../../stats/presentation/tempo_hint.dart';
import '../domain/live_recorder.dart';
import '../domain/live_x01.dart';
import 'autodarts_live_controller.dart';
import 'autodarts_live_screen.dart';
import 'live_correction_sheet.dart';

/// Autodarts Live in der Arena-Spielansicht: Wurfleiste mit den Darts der
/// Aufnahme, Board mit den echten Positionen und eine Tafel für dich.
///
/// Es gibt **keinen Gegner**: Die Darts des Gegners sieht DartLab nicht (siehe
/// docs/autodarts-live.md). Gezeigt wird nur, was die Daten hergeben, die
/// rechte Spalte gehört deshalb den Kennzahlen der Session. Auf dem Telefon
/// stehen sie in einem Blatt (Symbol oben rechts).
///
/// Mit „X01 mitzählen“ zeigt die Tafel den Rest und die Aufnahmen des Legs
/// (Punkte | Rest). Ohne X01 gibt es keinen Rest: Dann steht der Rohschnitt
/// groß da, die Tabelle zeigt Punkte und laufenden Schnitt je Aufnahme.
class ArenaLiveView extends ConsumerStatefulWidget {
  const ArenaLiveView({super.key, required this.live});
  final LiveViewState live;

  @override
  ConsumerState<ArenaLiveView> createState() => _ArenaLiveViewState();
}

class _ArenaLiveViewState extends ConsumerState<ArenaLiveView> {
  /// Heatmap der Session auf dem Board zeigen.
  bool _heat = false;

  LiveViewState get live => widget.live;

  void _legEnd(LegMarkKind kind) {
    ref.read(autodartsLiveProvider.notifier).markLeg(kind);
    final start = live.x01Config?.startScore ?? 501;
    if (kind == LegMarkKind.lost) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.liveLegLostDone(start))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final x01 = live.x01;
    final stats = live.stats;
    final name = ref.watch(activePlayerProvider.select((p) => p?.name)) ?? l10n.arenaPlayerYou;
    final status = ref.watch(sourceStatusProvider).value ?? ref.watch(dartSourceProvider).status;
    final (host, port) = ref.watch(settingsProvider.select((s) => (s.autodartsHost, s.autodartsPort)));
    final offline = !status.isLive && status.phase != SourcePhase.idle;

    // Ohne X01 zeigt die Wurfleiste nach dem Takeout die letzte Aufnahme
    // (gedämpft), mit X01 die neue mit dem Weg.
    final showLast = x01 == null && live.current.isEmpty && live.lastVisit != null;
    final darts = showLast ? live.lastVisit! : live.current;
    final visitSum = darts.fold<int>(0, (a, d) => a + d.score);
    final waiting = live.current.isEmpty && live.lastVisit == null;
    final shownVisit = showLast ? live.closedCount - 1 : live.closedCount;
    final fixable = !live.ended;

    // Weg bzw. Stell-Vorschlag nur, solange die Aufnahme noch Darts hat.
    final open = x01 != null && x01.dartsLeft > 0;
    final route = open ? x01.suggestion : null;
    final setup = open && route == null ? x01.setup : null;
    final plan = route ?? setup?.darts;
    final event = x01?.lastEvent;

    final slots = [
      for (var i = 0; i < LiveRecorder.dartsPerVisit; i++)
        ArenaDartSlot(
          slotKey: Key('live-slot-$i'),
          segment: i < darts.length ? darts[i].segment : null,
          planned: plan != null && i >= darts.length && i - darts.length < plan.length ? plan[i - darts.length] : null,
          plannedColor: route != null ? ArenaPalette.hint : colors.setupHint,
          edited: i < darts.length && LiveRecorder.isManual(darts[i]),
          editedTooltip: l10n.liveFixEdited,
          dim: showLast,
          addHint: fixable && i == darts.length,
          addTooltip: l10n.liveFixAddDart,
          onTap: !fixable
              ? null
              : i < darts.length
              ? () => fixLiveDart(context, ref, visit: shownVisit, dart: i, current: darts[i], visitLength: darts.length)
              : i == darts.length
              ? () => addLiveDart(context, ref, visit: shownVisit)
              : null,
        ),
    ];

    final player = x01 != null ? _x01Player(name, x01) : _plainPlayer(name);

    final messages = ArenaMessages(
      hint: route != null && route.isNotEmpty
          ? '${l10n.visitRoute}: ${route.map((s) => s.name).join(' · ')}'
          : setup != null
          ? l10n.visitSetup(setup.leave)
          : null,
      hintKey: route != null && route.isNotEmpty ? const Key('live-route-label') : const Key('live-setup-label'),
      hintColor: route != null ? ArenaPalette.hint : colors.setupHint,
      status: offline
          ? l10n.liveNotConnected('$host:$port')
          : live.ended
          ? null
          : waiting && x01 == null
          ? l10n.liveWaiting
          : x01 != null
          ? l10n.liveLegInfo(x01.legs.length + 1, x01.legsWon, x01.legsLost)
          : showLast
          ? l10n.liveVisitLast
          : l10n.liveVisitCurrent,
      statusKey: offline ? const Key('live-offline') : const Key('live-status'),
      statusMuted: !offline,
      statusColor: offline ? colors.warning : null,
      event: event == null ? null : (event == GameEventType.bust ? l10n.evBust : l10n.evCheckout('${x01!.legs.lastOrNull?.checkout ?? ''}')),
      eventKey: const Key('live-event'),
      eventColor: event == GameEventType.bust ? ArenaPalette.danger : ArenaPalette.success,
      tempo: tempoHintLine(ref, l10n, LiveTempo.ofVisits([...live.recentVisits.reversed, live.current])),
    );

    final hits = <BoardPoint>[for (final d in live.current) ?d.position];
    final board = BoardStatusFrame(
      child: DartboardView(
      key: const Key('live-board'),
      heat: stats.heat,
      showHeat: _heat,
      hits: hits,
      lastSegment: live.current.isEmpty ? null : live.current.last.segment,
      hitSerial: live.dartSerial,
      semanticsLabel: l10n.liveHeatmap,
      ),
    );

    final narrow = MediaQuery.sizeOf(context).width < 900;

    return ArenaScreen(
      players: [player],
      topBar: (compact, scale) => ArenaTopBar(
        leaveKey: const Key('live-leave'),
        onLeave: () => AutodartsLiveScreen.leave(context),
        chips: x01 != null
            ? ['${x01.config.startScore}', inOutCode(doubleIn: false, out: x01.config.outMode), l10n.liveTitle]
            : [l10n.liveTitle, l10n.arenaLiveChipPlain],
        trailing: [
          if (live.listening) SourceStatusBadge(compact: narrow),
          if (live.listening) const BoardHelpButton(),
          const SizedBox(width: AppSpacing.xs),
          // Breit steht die Session in der rechten Spalte, auf dem Telefon im Blatt.
          if (!ArenaScreen.isWide(MediaQuery.sizeOf(context)))
            IconButton(
              key: const Key('live-session-open'),
              tooltip: l10n.liveStatsTitle,
              icon: const Icon(Icons.insights_rounded),
              onPressed: () => showLiveSessionSheet(context, recentOnly: false),
            ),
          if (MediaQuery.sizeOf(context).width >= 600) const FullscreenButton(),
        ],
        compact: compact,
        scale: scale,
      ),
      dartSlots: slots,
      visitSum: visitSum,
      visitBust: event == GameEventType.bust && live.current.isNotEmpty,
      sumKey: const Key('live-visit-score'),
      board: board,
      messages: messages,
      messagesExtra: messages.tempo == null ? 0 : 18,
      sidePanel: const _SessionPanel(),
      actions: (height) => ArenaActionBar(
        height: height,
        undoKey: const Key('live-leg-lost'),
        onUndo: live.ended || x01 == null || x01.legDarts == 0 ? null : () => _legEnd(LegMarkKind.lost),
        undoLabel: l10n.liveLegLost,
        undoIcon: Icons.flag_outlined,
        showUndo: x01 != null,
        nextKey: const Key('live-end'),
        onNext: live.ended ? null : () => AutodartsLiveScreen.endSession(context, ref),
        nextLabel: l10n.liveEnd,
        nextIcon: Icons.stop_rounded,
        icons: [
          ArenaIconButton(
            key: const Key('live-corrections'),
            icon: Icons.edit_note_rounded,
            tooltip: l10n.liveRecent,
            size: height - 10,
            onPressed: () => showLiveSessionSheet(context, recentOnly: true),
          ),
          ArenaIconButton(
            key: const Key('live-heat-toggle'),
            icon: _heat ? Icons.grid_off_rounded : Icons.local_fire_department_rounded,
            tooltip: l10n.liveHeatmap,
            size: height - 10,
            onPressed: () => setState(() => _heat = !_heat),
          ),
          if (x01 != null)
            ArenaIconButton(
              key: const Key('live-leg-restart'),
              icon: Icons.restart_alt_rounded,
              tooltip: l10n.liveLegRestart,
              size: height - 10,
              onPressed: live.ended || x01.legDarts == 0 ? null : () => _legEnd(LegMarkKind.restart),
            ),
        ],
      ),
      result: live.ended ? SingleChildScrollView(child: _EndedCard(live: live)) : null,
    );
  }

  /// Tafel mit „X01 mitzählen“: Rest, Aufnahmen (Punkte | Rest), Schnitt.
  ArenaPlayer _x01Player(String name, LiveX01 x) {
    final rows = [
      for (final r in x.legRows)
        VisitRow(
          player: 0,
          leg: x.legs.length + 1,
          visit: r.visit,
          darts: const [],
          points: r.points,
          remaining: r.remaining,
          bust: r.bust,
          checkout: r.checkout,
        ),
    ];
    return ArenaPlayer(
      name: name,
      remaining: x.remaining,
      rows: rows,
      startScore: x.config.startScore,
      active: !live.ended,
      lastVisit: rows.isEmpty ? 0 : rows.last.points,
      legAverage: formatDecimal(x.legAverage ?? 0),
      matchAverage: formatDecimal(x.average ?? 0),
      legDarts: x.legDarts,
      legsText: context.l10n.liveLegsValue(x.legsWon, x.legsLost),
      remainingKey: const Key('live-remaining'),
      dartsKey: const Key('live-leg-darts'),
      legsKey: const Key('live-legs-won'),
      keyPrefix: 'live-visits',
    );
  }

  /// Tafel ohne X01: Rohschnitt groß, Punkte und laufender Schnitt je Aufnahme.
  ArenaPlayer _plainPlayer(String name) {
    final l10n = context.l10n;
    final s = live.stats;
    // Laufender Schnitt nach jeder der letzten Aufnahmen: vom Gesamtstand
    // nach der neuesten rückwärts abziehen (die laufende Aufnahme zählt nicht mit).
    var pts = s.points - live.current.fold<int>(0, (a, d) => a + d.score);
    var count = s.darts - live.current.length;
    final rows = <ArenaScoreRow>[];
    for (final (i, v) in live.recentVisits.indexed) {
      final p = v.fold<int>(0, (a, d) => a + d.score);
      rows.add(ArenaScoreRow(visit: live.closedCount - 1 - i, points: p, value: count == 0 ? '–' : formatDecimal(pts / count * 3)));
      pts -= p;
      count -= v.length;
    }
    final last = live.lastVisit;
    return ArenaPlayer(
      name: name,
      remaining: 0,
      rows: const [],
      startScore: 0,
      active: !live.ended,
      heroText: s.darts == 0 ? '–' : formatDecimal(s.rawAverage),
      caption: l10n.statRawAverage,
      lastVisit: last == null ? 0 : last.fold<int>(0, (a, d) => a + d.score),
      scoreRows: rows.reversed.toList(),
      scoreHeaders: (l10n.arenaLiveColPoints, l10n.arenaLiveColAvg),
      stats: [
        (l10n.arenaLiveVisitsShort, '${s.visits}'),
        (l10n.arenaLiveBest, s.visits == 0 ? '–' : '${s.bestVisit}'),
      ],
      legDarts: s.darts,
      dartsLabel: l10n.arenaLiveDartsSession,
      remainingKey: const Key('live-remaining'),
      dartsKey: const Key('live-leg-darts'),
      keyPrefix: 'live-visits',
    );
  }
}

/// Inhalt der Session: X01-Schalter, Kennzahlen, Treffer, letzte Aufnahmen,
/// Hinweis. Breit in der rechten Spalte, auf dem Telefon im Blatt.
class _SessionContent extends ConsumerWidget {
  const _SessionContent({required this.recentOnly});
  final bool recentOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(autodartsLiveProvider);
    const gap = SizedBox(height: AppSpacing.m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!recentOnly) ...[LiveX01Card(live: live), gap, LiveStatsCard(live: live), gap, LiveDistributionCard(stats: live.stats), gap],
        LiveRecentCard(live: live),
        if (!recentOnly) ...[gap, LiveHintCard(x01: live.x01 != null)],
      ],
    );
  }
}

/// Rechte Spalte der breiten Arena-Ansicht: die Session in einem Scroller.
class _SessionPanel extends StatelessWidget {
  const _SessionPanel();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('live-session-panel'),
      padding: EdgeInsets.zero,
      children: const [_SessionContent(recentOnly: false)],
    );
  }
}

/// Blatt mit der Session (Telefon) bzw. nur den letzten Aufnahmen zum
/// Korrigieren (Symbol in der Schalterleiste). Im dunklen Arena-Theme.
Future<void> showLiveSessionSheet(BuildContext context, {required bool recentOnly}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: ArenaPalette.background,
    builder: (context) => Theme(
      data: ArenaPalette.theme,
      child: SingleChildScrollView(
        key: const Key('live-session-sheet'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.xl),
        child: _SessionContent(recentOnly: recentOnly),
      ),
    ),
  );
}

/// Nach „Beenden“: die gespeicherte Session in der Mitte statt des Boards.
class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.live});
  final LiveViewState live;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = live.stats;
    final x = live.x01;
    final avg = x?.average ?? s.rawAverage;
    final cells = [
      (l10n.statDarts, '${s.darts}'),
      (x == null ? l10n.statRawAverage : l10n.statAverage, formatDecimal(avg)),
      (l10n.statBestVisit, s.visits == 0 ? '–' : '${s.bestVisit}'),
      (l10n.liveScores, '${s.count100} / ${s.count140} / ${s.count180}'),
    ];
    return Container(
      key: const Key('live-ended'),
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(color: ArenaPalette.surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.arenaLiveEndedTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            s.darts > 0 ? l10n.liveSaved(s.darts) : l10n.liveNothingSaved,
            key: const Key('live-ended-saved'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: ArenaPalette.textMuted),
          ),
          const SizedBox(height: AppSpacing.l),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.m,
            children: [
              for (final (label, value) in cells)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(color: ArenaPalette.textMuted, fontSize: 12.5)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
