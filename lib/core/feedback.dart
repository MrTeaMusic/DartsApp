import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/board/domain/segment.dart';
import '../features/dart_source/domain/dart_event.dart';
import '../features/dart_source/presentation/dart_source_providers.dart';
import 'settings/app_settings.dart';

/// Haptik und Sound bei jedem Dart, gemäß Einstellungen.
/// Wird einmal in der App-Wurzel aktiviert.
final dartFeedbackProvider = Provider<void>((ref) {
  ref.listen(dartEventsProvider, (_, next) {
    final event = next.value;
    if (event is! DartThrown) return;
    final settings = ref.read(settingsProvider);
    if (settings.hapticsEnabled && defaultTargetPlatform == TargetPlatform.iOS) {
      final s = event.dart.segment;
      if (s.isTriple || s.bed == Bed.innerBull) {
        HapticFeedback.heavyImpact();
      } else if (s.isMiss) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    }
    if (settings.soundEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  });
});
