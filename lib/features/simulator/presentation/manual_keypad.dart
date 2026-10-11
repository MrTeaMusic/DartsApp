import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../dart_source/data/manual_source.dart';
import 'segment_picker.dart';

/// Tastenfeld für die manuelle Eingabe: Multiplikator wählen, dann Zahl.
/// Nach jedem Dart springt der Multiplikator auf Single zurück.
class ManualKeypad extends StatefulWidget {
  const ManualKeypad({super.key, required this.source});
  final ManualSource source;

  @override
  State<ManualKeypad> createState() => _ManualKeypadState();
}

class _ManualKeypadState extends State<ManualKeypad> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.boardManualHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.m),
          SegmentPicker(onPick: widget.source.enter),
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
