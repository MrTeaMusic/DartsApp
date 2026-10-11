import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fullscreen.dart';
import '../l10n.dart';

/// Schaltet das Vollbild um (auch mit F11).
class FullscreenButton extends ConsumerWidget {
  const FullscreenButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(fullscreenProvider);
    final l10n = context.l10n;
    return IconButton(
      key: const Key('fullscreen-toggle'),
      tooltip: on ? l10n.fullscreenExit : l10n.fullscreenEnter,
      icon: Icon(on ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
      onPressed: ref.read(fullscreenProvider.notifier).toggle,
    );
  }
}
