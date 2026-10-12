import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../domain/achievement_tracker.dart';
import '../domain/achievements.dart';
import 'progress_providers.dart';
import 'progress_texts.dart';

/// Reiter „Erfolge“ der Statistik: Übersicht, zuletzt erreichte Stufen und
/// alle Erfolge nach Gruppen. Gesperrte erscheinen grau mit Fortschritt.
class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key, required this.wide, required this.pad});
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final list = ref.watch(achievementsProvider);
    final look = context.look;
    if (list == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      key: const Key('stats-list-achievements'),
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.xxl),
      children: [
        _Summary(list: list, wide: wide),
        for (final g in AchievementGroup.values) ...[
          const SectionGap(factor: 0.8),
          () {
            final items = [for (final a in list) if (a.def.group == g) a];
            final unlocked = items.fold(0, (s, a) => s + a.tier);
            final total = items.fold(0, (s, a) => s + a.def.maxTier);
            return SectionHeader(l10n.achievementGroup(g), trailing: Kicker(l10n.achGroupCount(unlocked, total)));
          }(),
          LayoutBuilder(builder: (context, c) {
            final columns = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
            final gap = look.gridGap;
            final width = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final a in list)
                  if (a.def.group == g) SizedBox(width: width, child: AchievementTile(status: a)),
              ],
            );
          }),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.list, required this.wide});
  final List<AchievementStatus> list;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final total = AchievementCatalog.totalTiers;
    final unlocked = list.fold(0, (s, a) => s + a.tier);
    // Medaillen je Farbe: Erfolge ohne Stufen zählen als Gold.
    var bronze = 0, silver = 0, gold = 0;
    for (final a in list) {
      if (!a.def.tiered) {
        if (a.unlocked) gold++;
        continue;
      }
      if (a.tier >= 1) bronze++;
      if (a.tier >= 2) silver++;
      if (a.tier >= 3) gold++;
    }
    final latest = [for (final a in list) if (a.unlockedAt != null) a]
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Kicker(l10n.achTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.achSummary(unlocked, total),
          key: const Key('achievements-summary'),
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.m),
        LookProgressBar(value: total == 0 ? 0 : unlocked / total, color: colors.medalGold),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.l,
          runSpacing: AppSpacing.s,
          children: [
            _MedalCount(color: colors.medalBronze, label: l10n.achTierBronze, count: bronze),
            _MedalCount(color: colors.medalSilver, label: l10n.achTierSilver, count: silver),
            _MedalCount(color: colors.medalGold, label: l10n.achTierGold, count: gold),
          ],
        ),
      ],
    );

    final recent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Kicker(l10n.achLatest),
        const SizedBox(height: AppSpacing.s),
        if (latest.isEmpty)
          Text(l10n.achNone, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted))
        else
          for (final a in latest.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  _Medal(def: a.def, tier: a.tier, size: 32),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      [l10n.achievementTitle(a.def.id), ?l10n.tierName(a.def, a.tier)].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Text(shortDate(a.unlockedAt!), style: look.kicker.copyWith(color: colors.textMuted)),
                ],
              ),
            ),
      ],
    );

    return AppCard(
      key: const Key('achievements-overview'),
      child: wide
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: head),
                  VerticalDivider(width: AppSpacing.xxl, color: theme.colorScheme.outline),
                  Expanded(child: recent),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [head, Divider(height: AppSpacing.xl, color: theme.colorScheme.outline), recent],
            ),
    );
  }
}

class _MedalCount extends StatelessWidget {
  const _MedalCount({required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.workspace_premium_rounded, color: color, size: 20),
        const SizedBox(width: AppSpacing.xs),
        Text('$count', style: look.chipNumber.copyWith(color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(width: AppSpacing.xs),
        Text(look.caps(label), style: look.kicker.copyWith(color: context.dartColors.textMuted)),
      ],
    );
  }
}

/// Rundes Abzeichen eines Erfolgs in der Farbe der Stufe, grau wenn
/// gesperrt.
class _Medal extends StatelessWidget {
  const _Medal({required this.def, required this.tier, this.size = 48});
  final AchievementDef def;
  final int tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final locked = tier <= 0;
    final color = locked ? colors.textMuted : tierColor(colors, def, tier);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: locked ? 0.10 : 0.18),
        border: Border.all(color: color.withValues(alpha: locked ? 0.35 : 0.9), width: locked ? 1 : 2),
      ),
      child: Icon(locked ? Icons.lock_outline_rounded : achievementIcon(def.id), color: color, size: size * 0.5),
    );
  }
}

/// Ein Erfolg mit Stufe, Beschreibung und Fortschritt bzw. Datum.
class AchievementTile extends StatelessWidget {
  const AchievementTile({super.key, required this.status});
  final AchievementStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final a = status;
    final d = a.def;
    final locked = !a.unlocked;
    final next = a.next;
    final tierName = l10n.tierName(d, a.tier);
    final muted = colors.textMuted;
    final barColor = tierColor(colors, d, a.complete ? a.tier : a.tier + 1);

    String progress() {
      if (next == null) return a.unlockedAt != null ? l10n.achUnlockedOn(shortDate(a.unlockedAt!)) : l10n.achAllTiers;
      final v = a.value;
      final target = _format(d, next);
      if (d.lowerIsBetter) return l10n.achBestTarget(v == null ? '–' : _format(d, v), target);
      return l10n.achProgress(v == null ? '0' : _format(d, v < next ? v : next), target);
    }

    return Opacity(
      opacity: locked ? 0.72 : 1,
      child: AppCard(
        key: Key('achievement-${d.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Medal(def: d, tier: a.tier),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.achievementTitle(d.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: locked ? muted : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (d.tiered) ...[
                        const SizedBox(width: AppSpacing.s),
                        _TierPips(def: d, tier: a.tier),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  // Immer zwei Zeilen hoch, damit die Kacheln einer Reihe gleich hoch sind.
                  Stack(
                    children: [
                      Text('\n', style: theme.textTheme.bodySmall),
                      Text(
                        l10n.achievementDescription(d.id),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s),
                  LookProgressBar(value: a.ratio, color: barColor, height: 6),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          progress(),
                          key: Key('achievement-${d.id}-progress'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: look.kicker.copyWith(color: muted),
                        ),
                      ),
                      if (tierName != null)
                        Text(look.caps(tierName), style: look.kicker.copyWith(color: tierColor(colors, d, a.tier))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(AchievementDef d, num v) => switch (d.metric) {
        AchievementMetric.bestAverage => formatDecimal(v),
        _ => groupedNumber(v),
      };
}

/// Drei Punkte für Bronze, Silber, Gold; erreichte in ihrer Farbe.
class _TierPips extends StatelessWidget {
  const _TierPips({required this.def, required this.tier});
  final AchievementDef def;
  final int tier;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= def.maxTier; i++)
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= tier ? tierColor(colors, def, i) : colors.surfaceHigh,
            ),
          ),
      ],
    );
  }
}
