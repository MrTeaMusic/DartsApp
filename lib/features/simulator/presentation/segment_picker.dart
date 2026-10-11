import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/domain/segment.dart';

/// Feldauswahl: Multiplikator wählen, dann Zahl, Bull oder Miss.
/// Nach jeder Auswahl springt der Multiplikator auf Single zurück.
class SegmentPicker extends StatefulWidget {
  const SegmentPicker({super.key, required this.onPick, this.keyPrefix = 'key'});

  final ValueChanged<Segment> onPick;

  /// Präfix für die Widget-Keys (z. B. `key-20`, `fix-20`).
  final String keyPrefix;

  @override
  State<SegmentPicker> createState() => _SegmentPickerState();
}

class _SegmentPickerState extends State<SegmentPicker> {
  int _multiplier = 1;

  void _pick(Segment s) {
    widget.onPick(s);
    if (mounted) setState(() => _multiplier = 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final p = widget.keyPrefix;
    final numberColor = switch (_multiplier) {
      3 => colors.tripleHit,
      2 => colors.doubleHit,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 1, label: Text(l10n.single)),
            ButtonSegment(value: 2, label: Text(l10n.double, key: Key('$p-double'))),
            ButtonSegment(value: 3, label: Text(l10n.triple, key: Key('$p-triple'))),
          ],
          selected: {_multiplier},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _multiplier = s.first),
        ),
        const SizedBox(height: AppSpacing.m),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.s,
          crossAxisSpacing: AppSpacing.s,
          childAspectRatio: 1.25,
          children: [
            for (var n = 1; n <= 20; n++)
              _Key(
                key: Key('$p-$n'),
                label: '$n',
                color: numberColor,
                onTap: () => _pick(Segment.fromNumber(n, _multiplier)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          children: [
            Expanded(child: _Key(key: Key('$p-25'), label: '25', color: colors.doubleHit, onTap: () => _pick(Segment.outerBull))),
            const SizedBox(width: AppSpacing.s),
            Expanded(child: _Key(key: Key('$p-bull'), label: 'BULL', color: colors.boardRed, onTap: () => _pick(Segment.bull))),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: _Key(key: Key('$p-miss'), label: l10n.boardMiss, color: colors.textMuted, onTap: () => _pick(Segment.miss)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface;
    return Material(
      color: context.dartColors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppRadii.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.s),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(child: Text(label, style: theme.textTheme.titleMedium?.copyWith(color: c))),
        ),
      ),
    );
  }
}

/// Fragt ein Feld ab, z. B. zum Korrigieren eines Darts.
Future<Segment?> showSegmentPicker(BuildContext context, {required String title, String? subtitle}) {
  return showModalBottomSheet<Segment>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.l),
            SegmentPicker(keyPrefix: 'fix', onPick: (s) => Navigator.pop(context, s)),
          ],
        ),
      ),
    ),
  );
}
