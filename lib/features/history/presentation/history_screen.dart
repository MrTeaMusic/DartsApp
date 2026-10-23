import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../games/presentation/game_texts.dart';
import '../../stats/presentation/stats_widgets.dart';
import '../data/history_repository.dart';
import '../domain/session_history.dart';

/// Höchstbreite von Verlauf und Detailansicht.
const double kHistoryMaxWidth = 860;

/// Spielverlauf: alle abgeschlossenen Sessions des aktiven Profils, nach Tag
/// gruppiert, mit Filter Training/Matches. Antippen öffnet die Session.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(historyProvider);
    final filter = ref.watch(historyFilterProvider);
    final all = async.value;
    final entries = all == null ? null : [for (final e in all) if (e.matches(filter)) e];

    return Scaffold(
      appBar: AppPageBar(maxWidth: kHistoryMaxWidth, title: Text(l10n.histTitle)),
      body: LayoutBuilder(builder: (context, c) {
        final look = context.look;
        final pad = AppPageBar.contentInset(context, c.maxWidth, kHistoryMaxWidth);
        final days = entries == null ? const <_Day>[] : _Day.group(entries);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, AppSpacing.s, pad, AppSpacing.s),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in HistoryFilter.values) ...[
                      ChoiceChip(
                        key: Key('history-filter-${f.name}'),
                        label: Text(switch (f) {
                          HistoryFilter.all => l10n.histFilterAll,
                          HistoryFilter.training => l10n.histFilterTraining,
                          HistoryFilter.matches => l10n.histFilterMatches,
                        }),
                        selected: f == filter,
                        onSelected: (_) => ref.read(historyFilterProvider.notifier).set(f),
                      ),
                      const SizedBox(width: AppSpacing.s),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: entries == null
                  ? const SizedBox.shrink()
                  : all!.isEmpty
                      ? ComingSoon(icon: Icons.history_rounded, title: l10n.histEmpty, text: l10n.histEmptyText)
                      : entries.isEmpty
                          ? Center(child: Text(l10n.histEmptyFilter, style: Theme.of(context).textTheme.bodyMedium))
                          : ListView.builder(
                              key: const Key('history-list'),
                              padding: EdgeInsets.fromLTRB(pad, AppSpacing.xs, pad, pad),
                              itemCount: days.length,
                              itemBuilder: (context, i) => Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : look.sectionGap * 0.6),
                                child: _DayGroup(day: days[i]),
                              ),
                            ),
            ),
          ],
        );
      }),
    );
  }
}

/// Sessions eines Kalendertags.
class _Day {
  _Day(this.day, this.entries);
  final DateTime day;
  final List<HistoryEntry> entries;

  static List<_Day> group(List<HistoryEntry> entries) {
    final out = <_Day>[];
    for (final e in entries) {
      final d = DateTime(e.startedAt.year, e.startedAt.month, e.startedAt.day);
      if (out.isEmpty || out.last.day != d) out.add(_Day(d, []));
      out.last.entries.add(e);
    }
    return out;
  }
}

/// „Heute“, „Gestern“ oder „Mi, 8.10.2026“.
String historyDayLabel(AppLocalizations l10n, DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  if (day == today) return l10n.histToday;
  if (day == DateTime(today.year, today.month, today.day - 1)) return l10n.histYesterday;
  final names = l10n.statsWeekdayNames.split(',');
  return '${names[(day.weekday - 1) % names.length]}, ${formatDate(day)}';
}

String historyTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.day});
  final _Day day;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final look = context.look;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s, left: AppSpacing.xxs),
          child: Kicker(historyDayLabel(l10n, day.day)),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final (i, e) in day.entries.indexed) ...[
                if (i > 0) Divider(indent: look.cardPadding + 52, endIndent: look.cardPadding),
                HistoryTile(entry: e),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Eine Zeile im Verlauf: Spiel, Uhrzeit, Darts, Kennzahl bzw. Ergebnis.
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final e = entry;
    final minutes = e.duration?.inMinutes;
    final subtitle = [
      if (e.hasOpponent && e.opponents.isNotEmpty) l10n.histVs(e.opponents.join(', ')),
      historyTime(e.startedAt),
      if (e.hasLiveLegs && !e.isImported) l10n.onlineLegs(e.legsWon, e.legsLost),
      if (!e.finished) l10n.gameAborted,
      l10n.sessionAmount(e.gameId, e.darts, e.metrics),
      if (minutes != null && minutes > 0) formatMinutes(minutes),
    ].join(' · ');
    final title = e.isImported ? l10n.histOnlineMatch : l10n.gameTitle(e.gameId);

    final Widget trailing;
    if (e.hasOpponent) {
      final won = e.won;
      final color = won == null ? colors.textMuted : (won ? colors.success : colors.danger);
      trailing = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            won == null ? l10n.histAborted : (won ? l10n.histWon : l10n.histLost),
            style: look.kicker.copyWith(color: color),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${e.legsWon}:${e.legsLost}',
            style: look.chipNumber.copyWith(color: theme.colorScheme.onSurface),
          ),
        ],
      );
    } else {
      final m = e.keyMetric;
      trailing = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            // Ohne Kennzahl (z. B. abgebrochen, wo nur vollständige Spiele
            // zählen) stehen die geworfenen Darts.
            m == null ? '${e.darts} ${l10n.statDarts}' : formatMetricKey(e.gameId, m.key, m.value),
            style: look.chipNumber.copyWith(color: theme.colorScheme.onSurface),
          ),
          if (m != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Kicker(metricLabel(l10n, m.key)),
            ),
          ],
        ],
      );
    }

    return InkWell(
      key: Key('history-${e.id}'),
      onTap: () => context.go(Routes.session(e.id)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: look.cardPadding, vertical: AppSpacing.m),
        child: Row(
          children: [
            IconBadge(icon: gameIcon(e.gameId), size: 40),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (e.tournament) ...[
                        const SizedBox(width: AppSpacing.s),
                        Icon(Icons.account_tree_rounded, size: 16, color: colors.textMuted),
                      ],
                      if (e.isOnline) ...[
                        const SizedBox(width: AppSpacing.s),
                        Icon(Icons.public_rounded, key: Key('history-online-${e.id}'), size: 16, color: colors.textMuted),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            trailing,
          ],
        ),
      ),
    );
  }
}
