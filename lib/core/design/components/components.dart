import 'package:flutter/material.dart';

import '../../../features/board/domain/segment.dart';
import '../app_theme.dart';
import '../dart_colors.dart';
import '../tokens.dart';

/// Karte mit einheitlichem Innenabstand.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.l),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Überschrift über einem Abschnitt.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m, top: AppSpacing.s),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Kennzahl mit großer Zahl, z. B. "3-Dart-Average 54,3".
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: context.dartColors.textMuted),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(value, style: theme.textTheme.displayMedium),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(caption!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Kleines Statusschild mit farbigem Punkt.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.pulsing = false,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool pulsing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.xs + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: color, pulsing: pulsing),
              const SizedBox(width: AppSpacing.s),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulsing && _c.isAnimating) {
      _c
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.pulsing ? Tween(begin: 0.35, end: 1.0).animate(_c) : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Anzeige eines geworfenen Felds, eingefärbt nach Multiplikator.
class DartChip extends StatelessWidget {
  const DartChip({super.key, this.segment, this.large = false});

  /// `null` = noch nicht geworfen (Platzhalter).
  final Segment? segment;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final s = segment;
    final Color accent = switch (s) {
      null => colors.textMuted,
      final s when s.isMiss => colors.textMuted,
      final s when s.isTriple => colors.boardRed,
      final s when s.isDouble => colors.boardGreen,
      _ => theme.colorScheme.onSurface,
    };
    final size = large ? 92.0 : 64.0;
    return AnimatedContainer(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      width: size * 1.35,
      height: size,
      decoration: BoxDecoration(
        color: s == null ? Colors.transparent : accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.m),
        border: Border.all(color: s == null ? theme.colorScheme.outline : accent.withValues(alpha: 0.6), width: 1.5),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: AppDurations.medium,
        transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
        child: Text(
          s?.name ?? '–',
          key: ValueKey(s?.name),
          style: (large ? AppTypography.scoreMedium : theme.textTheme.titleLarge)?.copyWith(
            color: s == null ? colors.textMuted : accent,
            fontFeatures: AppTypography.tabular,
          ),
        ),
      ),
    );
  }
}

/// Hinweis für Funktionen, die erst in einer späteren Phase kommen.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.text, this.icon = Icons.construction_rounded});

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: AppSpacing.l),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.s),
              Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: context.dartColors.textMuted), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
