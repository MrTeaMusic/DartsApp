import 'package:flutter/material.dart';

import '../../../features/board/domain/segment.dart';
import '../app_theme.dart';
import '../dart_colors.dart';
import '../dart_look.dart';
import '../tokens.dart';
import 'components.dart';

/// Auswahlkachel eines Looks mit echter Miniatur-Vorschau: Die Vorschau
/// wird mit dem Theme des Looks gebaut und verkleinert.
class LookPickerTile extends StatelessWidget {
  const LookPickerTile({
    super.key,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.previewLabel,
    required this.selected,
    required this.onTap,
    this.brightness = Brightness.dark,
    this.horizontal = false,
  });

  final DartLookId id;
  final String title;
  final String subtitle;

  /// Beschriftung der Mini-Anzeige („Rest“).
  final String previewLabel;
  final bool selected;
  final VoidCallback onTap;

  /// Helligkeit der Vorschau (nur Clean hat eine helle Variante).
  final Brightness brightness;

  /// Vorschau links, Text rechts (für schmale Bildschirme).
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final radius = BorderRadius.circular(look.radiusL);
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular((look.radiusL - 4).clamp(2, 40)),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.cover,
              child: Theme(
                data: AppTheme.build(id, brightness),
                child: _Preview(label: previewLabel),
              ),
            ),
          ),
        ),
      ),
    );
    final titleRow = Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
        AnimatedOpacity(
          opacity: selected ? 1 : 0,
          duration: AppDurations.fast,
          child: Icon(Icons.check_circle_rounded, size: 20, color: accent),
        ),
      ],
    );
    final text = Text(subtitle, style: theme.textTheme.bodySmall, maxLines: horizontal ? 3 : 2, overflow: TextOverflow.ellipsis);
    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? accent : theme.colorScheme.outline, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s),
            child: horizontal
                ? Row(
                    children: [
                      SizedBox(width: 132, child: preview),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [titleRow, const SizedBox(height: AppSpacing.xxs), text],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      preview,
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.m, AppSpacing.xs, AppSpacing.xs),
                        child: titleRow,
                      ),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs), child: text),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Feste 320×200-Szene: Navigationsleiste, Restpunkte, drei Darts.
class _Preview extends StatelessWidget {
  const _Preview({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final rail = theme.navigationRailTheme;
    return Container(
      width: 320,
      height: 200,
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 44,
            decoration: BoxDecoration(
              color: rail.backgroundColor,
              border: Border(right: BorderSide(color: theme.colorScheme.outline)),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.s),
                    width: 28,
                    height: 20,
                    decoration: ShapeDecoration(
                      color: i == 0 ? rail.indicatorColor : Colors.transparent,
                      shape: rail.indicatorShape ?? const StadiumBorder(),
                    ),
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: i == 0 ? rail.selectedIconTheme?.color : colors.textMuted.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(look.pill ? 5 : 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ScorePanel(
                      label: label,
                      active: look.isArena ? true : null,
                      trailing: '3/10',
                      value: Text('36', style: ScorePanel.valueStyle(context, hero: false).copyWith(fontSize: 46)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  SizedBox(
                    height: 46,
                    child: Row(
                      children: [
                        for (final (i, (s, p)) in [
                          (Segment.triple(15), null),
                          (null, Segment.fromNumber(18, 2)),
                          (null, null),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.xs),
                          Expanded(child: FittedBox(child: DartChip(segment: s, planned: p, large: true))),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
