import 'package:flutter/material.dart';

import '../dart_look.dart';
import '../tokens.dart';
import 'components.dart';

/// Einblendung eines Ereignisses (Checkout, Bust, 180, Leg gewonnen).
///
/// * TV: volle Farbfläche wie eine Einblendung im Fernsehen.
/// * Clean: ruhige getönte Fläche.
/// * Lab: feiner Rahmen mit Farbkante links.
///
/// [kicker] steht klein vor dem Text, wenn der Text allein nur eine Zahl
/// oder ein Feld ist („Treffer · 14“).
class LookBanner extends StatelessWidget {
  const LookBanner({super.key, required this.text, required this.color, this.textKey, this.kicker});

  final String text;
  final Color color;
  final Key? textKey;
  final String? kicker;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);

    Widget content(Color fg, TextStyle? style) {
      final main = Text(text, key: textKey, style: style?.copyWith(color: fg));
      if (kicker == null) return main;
      return Row(
        // Kein Grundlinien-Ausrichten: Lab misst die Höhe mit IntrinsicHeight.
        children: [
          Kicker(kicker!, color: fg.withValues(alpha: 0.8)),
          const SizedBox(width: AppSpacing.m),
          Flexible(child: main),
        ],
      );
    }

    return switch (look.id) {
      DartLookId.tv => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s + 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(look.radiusM)),
          child: content(
            ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black,
            theme.textTheme.headlineSmall,
          ),
        ),
      DartLookId.clean => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l + 4, vertical: AppSpacing.m + 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(look.radiusL)),
          child: content(color, theme.textTheme.headlineSmall),
        ),
      DartLookId.lab => Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(look.radiusM),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s + 2),
                    child: content(color, theme.textTheme.titleLarge),
                  ),
                ),
              ],
            ),
          ),
        ),
    };
  }
}
