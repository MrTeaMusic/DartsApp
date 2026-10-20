import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/tournament.dart';
import 'match_controller.dart';
import 'match_routes.dart';
import 'match_texts.dart';
import 'tournament_bracket.dart';
import 'tournament_controller.dart';

/// Turnierbaum mit dem nächsten eigenen Spiel.
class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key});

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tourDiscardTitle),
        content: Text(l10n.tourDiscardText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cpuCancel)),
          FilledButton(
            key: const Key('confirm-discard-tournament'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.tourDiscard),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(tournamentControllerProvider.notifier).discard();
    if (context.mounted) context.go(MatchRoutes.hub);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = ref.watch(tournamentControllerProvider);
    // Nach einem Spiel neu zeichnen (Ergebnis wurde eingetragen).
    ref.watch(matchControllerProvider.select((s) => s?.ended));

    return Scaffold(
      appBar: AppPageBar(
        title: Text(l10n.tournamentTitle),
        actions: [
          if (t != null)
            PopupMenuButton<String>(
              key: const Key('tournament-menu'),
              onSelected: (v) => switch (v) {
                'new' => context.go(MatchRoutes.tournamentNew),
                _ => _discard(context, ref),
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'new', child: Text(l10n.tourNew)),
                PopupMenuItem(value: 'discard', key: const Key('tournament-discard'), child: Text(l10n.tourDiscard)),
              ],
            ),
        ],
      ),
      body: t == null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(context.look.page),
                child: ComingSoon(
                  icon: Icons.emoji_events_rounded,
                  title: l10n.tournamentTitle,
                  text: l10n.tourNone,
                  action: FilledButton.icon(
                    onPressed: () => context.go(MatchRoutes.tournamentNew),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.tourNew),
                  ),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final look = context.look;
                final page = look.pagePadding(c.maxWidth >= kWidePage);
                Widget padded(Widget child) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: page),
                  child: child,
                );
                return ListView(
                  key: const Key('tournament-scroll'),
                  padding: EdgeInsets.only(top: look.page * 0.5, bottom: page),
                  children: [
                    padded(_StatusCard(tournament: t)),
                    const SizedBox(height: AppSpacing.s),
                    padded(
                      Text(
                        l10n.tourInfo(t.startScore, (t.difficulty * 100).round()),
                        style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted),
                      ),
                    ),
                    const SectionGap(factor: 0.6),
                    _BracketView(tournament: t, viewport: c.maxWidth, page: page),
                  ],
                );
              },
            ),
    );
  }
}

/// Kartenbreite, bis zu der Knöpfe die ganze Breite nutzen (Telefon).
const double _phoneCard = 480;

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.tournament});
  final Tournament tournament;

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(tournamentControllerProvider.notifier);
    final saved = controller.savedMatch();
    final setup = saved?.setup ?? controller.nextMatchSetup();
    if (setup == null) return;
    await ref.read(matchControllerProvider.notifier).start(setup, resume: saved);
    if (context.mounted) context.go(MatchRoutes.play);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final t = tournament;
    final controller = ref.read(tournamentControllerProvider.notifier);
    final h = t.humanIndex;

    if (t.finished) {
      final won = t.champion == h;
      return AppCard(
        child: Row(
          children: [
            IconBadge(icon: Icons.emoji_events_rounded, size: 52, color: won ? colors.record : theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.l),
            Expanded(
              child: Text(
                won ? l10n.tourYouWon : l10n.tourChampion(t.entrants[t.champion!].name),
                key: const Key('tournament-champion'),
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
      );
    }

    final m = t.humanMatch;
    if (m != null) {
      final opponent = m.a == h ? m.b! : m.a!;
      final saved = controller.savedMatch();
      final look = context.look;
      final play = FilledButton.icon(
        key: const Key('tournament-play'),
        onPressed: () => _play(context, ref),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        ),
        icon: Icon(saved != null ? Icons.play_circle_outline_rounded : Icons.play_arrow_rounded),
        label: Text(saved != null ? l10n.tourResumeMatch : l10n.tourPlay),
      );
      final info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Kicker(l10n.tourNextMatch, color: look.isArena ? Colors.white.withValues(alpha: 0.9) : theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.s),
          Text(
            '${l10n.tourRoundName(m.round)} · ${l10n.tourBestOf(t.bestOf[m.round])}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${t.entrants[h].name} ${l10n.tourVs} ${t.entrants[opponent].name}',
            key: const Key('tournament-next'),
            style: look.sectionTitle.copyWith(
              fontSize: look.id == DartLookId.tv ? 34 : 26,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            l10n.tourCpuAverage(t.botAverage(opponent).round()),
            style: theme.textTheme.bodySmall?.copyWith(color: look.isArena ? Colors.white.withValues(alpha: 0.88) : colors.textMuted),
          ),
        ],
      );
      return HeroBackdrop(
        padding: EdgeInsets.all(look.cardPadding + AppSpacing.xs),
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 640
              // Breit: Knopf mit eigener Breite rechts unten neben dem Text.
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: AppSpacing.xl),
                    play,
                  ],
                )
              // Schmal: Knopf darunter, auf dem Telefon über die ganze
              // Breite, sonst mit eigener Breite rechtsbündig.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: AppSpacing.l),
                    if (c.maxWidth < _phoneCard) play else Align(alignment: Alignment.centerRight, child: play),
                  ],
                ),
        ),
      );
    }

    // Ausgeschieden: Rest simulieren.
    final out = t.rounds.expand((r) => r).where((x) => x.played && x.involves(h) && x.winner != h).firstOrNull;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (out != null) Text(l10n.tourEliminated(l10n.tourRoundName(out.round)), style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.m),
          LayoutBuilder(
            builder: (context, c) {
              final simRound = OutlinedButton(
                key: const Key('tournament-sim-round'),
                onPressed: controller.simulateRound,
                child: Text(l10n.tourSimRound, textAlign: TextAlign.center),
              );
              final simAll = FilledButton(
                key: const Key('tournament-sim-all'),
                onPressed: controller.simulateToEnd,
                child: Text(l10n.tourSimAll, textAlign: TextAlign.center),
              );
              // Telefon: beide Knöpfe teilen sich die Breite, sonst rechtsbündig.
              final phone = c.maxWidth < _phoneCard;
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (phone) Expanded(child: simRound) else simRound,
                  const SizedBox(width: AppSpacing.m),
                  if (phone) Expanded(child: simAll) else simAll,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollbarer Turnierbaum. Passt er nicht in die Breite, startet
/// die Ansicht bei der laufenden Runde.
class _BracketView extends StatefulWidget {
  const _BracketView({required this.tournament, required this.viewport, required this.page});
  final Tournament tournament;
  final double viewport;
  final double page;

  @override
  State<_BracketView> createState() => _BracketViewState();
}

class _BracketViewState extends State<_BracketView> {
  ScrollController? _scroll;

  /// Runde, auf die die Ansicht zuletzt ausgerichtet wurde. Das Turnier wird
  /// an Ort und Stelle geändert, daher merkt sich der State die Zahl.
  int? _round;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final g = BracketGeometry.forWidth(widget.viewport - widget.page * 2);
    final content = g.size.width + widget.page * 2;
    final overflow = (content - widget.viewport).clamp(0.0, double.infinity);
    // Vorrunde und laufende Runde nebeneinander, die Linien dazwischen.
    final target = (t.currentRound < 1 ? 0.0 : g.x(t.currentRound - 1)).clamp(0.0, overflow);
    if (_scroll == null) {
      _scroll = ScrollController(initialScrollOffset: target);
    } else if (_round != t.currentRound) {
      // Runde beendet: zur neuen Runde mitscrollen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scroll = _scroll;
        if (!mounted || scroll == null || !scroll.hasClients) return;
        scroll.animateTo(
          target.clamp(0.0, scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      });
    }
    _round = t.currentRound;
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        key: const Key('tournament-bracket-scroll'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(widget.page, 0, widget.page, AppSpacing.l),
        child: TournamentBracket(tournament: t, geometry: g),
      ),
    );
  }
}
