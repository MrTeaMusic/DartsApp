import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/data/manual_source.dart';

/// Tastenfeld für die manuelle Eingabe: Multiplikator wählen, dann Zahl.
/// Nach jedem Dart springt der Multiplikator auf Single zurück.
class ManualKeypad extends StatefulWidget {
  const ManualKeypad({super.key, required this.source});
  final ManualSource source;

  @override
  State<ManualKeypad> createState() => _ManualKeypadState();
}

class _ManualKeypadState extends State<ManualKeypad> {
  int _multiplier = 1;

  void _enter(Segment s) {
    widget.source.enter(s);
    setState(() => _multiplier = 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.boardManualHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.m),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 1, label: Text(l10n.single)),
              ButtonSegment(value: 2, label: Text(l10n.double)),
              ButtonSegment(value: 3, label: Text(l10n.triple)),
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
                  key: Key('key-$n'),
                  label: '$n',
                  onTap: () => _enter(Segment.fromNumber(n, _multiplier)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Expanded(
                child: _Key(
                  label: '25',
                  color: colors.boardGreen,
                  onTap: () => _enter(Segment.outerBull),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: _Key(
                  label: 'BULL',
                  color: colors.boardRed,
                  onTap: () => _enter(Segment.bull),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: _Key(
                  key: const Key('key-miss'),
                  label: l10n.boardMiss,
                  color: colors.textMuted,
                  onTap: () => _enter(Segment.miss),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.source.undoLast,
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.boardUndo),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('manual-next'),
                  onPressed: () => widget.source.nextVisit(fillWithMisses: true),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(l10n.boardNext),
                ),
              ),
            ],
          ),
        ],
      ),
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
          child: Center(
            child: Text(label, style: theme.textTheme.titleMedium?.copyWith(color: c)),
          ),
        ),
      ),
    );
  }
}
