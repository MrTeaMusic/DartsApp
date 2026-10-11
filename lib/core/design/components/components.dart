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

/// Farbe für ein Feld nach Multiplikator: Triple lila, Double grün.
Color segmentColor(BuildContext context, Segment s) {
  final colors = context.dartColors;
  if (s.isMiss) return colors.textMuted;
  if (s.isTriple) return colors.tripleHit;
  if (s.isDouble) return colors.doubleHit;
  return Theme.of(context).colorScheme.onSurface;
}

/// Anzeige eines geworfenen Felds, eingefärbt nach Multiplikator.
///
/// Ist noch kein Dart geworfen, kann [planned] den empfohlenen Wurf zeigen
/// (gelb, z. B. der Checkout-Weg).
class DartChip extends StatelessWidget {
  const DartChip({super.key, this.segment, this.planned, this.large = false, this.onTap, this.label});

  /// `null` = noch nicht geworfen (Platzhalter).
  final Segment? segment;

  /// Empfohlenes Feld für einen noch nicht geworfenen Dart.
  final Segment? planned;
  final bool large;

  /// Antippen, z. B. zum Korrigieren.
  final VoidCallback? onTap;

  /// Kleine Beschriftung oben links, z. B. „1“.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final s = segment;
    final p = s == null ? planned : null;
    final Color accent = s != null ? segmentColor(context, s) : (p != null ? colors.highlight : colors.textMuted);
    final size = large ? 92.0 : 64.0;
    final text = s?.name ?? p?.name ?? '–';
    final radius = BorderRadius.circular(AppRadii.m);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: Curves.easeOutCubic,
          width: size * 1.35,
          height: size,
          decoration: BoxDecoration(
            color: s != null
                ? accent.withValues(alpha: 0.14)
                : p != null
                    ? accent.withValues(alpha: 0.06)
                    : colors.surfaceHigh.withValues(alpha: 0.5),
            borderRadius: radius,
            border: Border.all(
              color: s != null
                  ? accent.withValues(alpha: 0.65)
                  : p != null
                      ? accent.withValues(alpha: 0.45)
                      : theme.colorScheme.outline,
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              if (label != null)
                Positioned(
                  left: 8,
                  top: 6,
                  child: Text(label!, style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted)),
                ),
              if (onTap != null && s != null)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Icon(Icons.edit_rounded, size: large ? 14 : 12, color: colors.textMuted.withValues(alpha: 0.7)),
                ),
              Center(
                child: AnimatedSwitcher(
                  duration: AppDurations.medium,
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
                  child: Text(
                    text,
                    key: ValueKey('${s == null ? 'p' : 's'}$text'),
                    style: (large ? AppTypography.scoreMedium : theme.textTheme.titleLarge)?.copyWith(
                      color: s == null && p == null ? colors.textMuted : accent,
                      fontFeatures: AppTypography.tabular,
                      fontWeight: p != null ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
            ],
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
