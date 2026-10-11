import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/l10n.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: ComingSoon(
        icon: Icons.insights_rounded,
        title: l10n.statsComingTitle,
        text: l10n.statsComingText,
      ),
    );
  }
}
