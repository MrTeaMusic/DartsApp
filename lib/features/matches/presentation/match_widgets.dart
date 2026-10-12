import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';

/// Beschriftete Auswahl aus festen Werten als Chips.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    required this.keyPrefix,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            for (final v in values)
              ChoiceChip(
                key: Key('$keyPrefix-$v'),
                label: Text(labelOf(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// Zahl mit Minus/Plus, z. B. Legs zum Sieg.
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.keyPrefix,
    this.step = 1,
    this.caption,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String keyPrefix;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              if (caption != null) Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        IconButton.outlined(
          key: Key('$keyPrefix-minus'),
          onPressed: value > min ? () => onChanged((value - step).clamp(min, max)) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$value',
            key: Key('$keyPrefix-value'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        IconButton.outlined(
          key: Key('$keyPrefix-plus'),
          onPressed: value < max ? () => onChanged((value + step).clamp(min, max)) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
