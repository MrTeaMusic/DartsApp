import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/settings/app_settings.dart';
import '../data/autodarts_local_source.dart';
import '../data/manual_source.dart';
import '../data/raw_message_log.dart';
import '../data/simulator_source.dart';
import '../domain/dart_event.dart';
import '../domain/dart_source.dart';

/// Erzeugt eine Quelle. In Tests überschreibbar.
typedef DartSourceFactory = DartSource Function(DartSourceKind kind, String host, int port);

final dartSourceFactoryProvider = Provider<DartSourceFactory>((ref) {
  final calibration = ref.watch(settingsProvider.select((s) => s.coordCalibration));
  return (kind, host, port) => switch (kind) {
        DartSourceKind.simulator => SimulatorSource(),
        DartSourceKind.manual => ManualSource(),
        DartSourceKind.autodartsLocal => AutodartsLocalSource(host: host, port: port, calibration: calibration),
      };
});

/// Die aktive Quelle laut Einstellungen. Alle Spiele lesen nur hierüber.
final dartSourceProvider = Provider<DartSource>((ref) {
  final (kind, host, port) = ref.watch(
    settingsProvider.select((s) => (s.sourceKind, s.autodartsHost, s.autodartsPort)),
  );
  final source = ref.watch(dartSourceFactoryProvider)(kind, host, port);
  unawaited(source.start());
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

final dartEventsProvider = StreamProvider<DartEvent>((ref) {
  return ref.watch(dartSourceProvider).events;
});

final sourceStatusProvider = StreamProvider<SourceStatus>((ref) async* {
  final source = ref.watch(dartSourceProvider);
  yield source.status;
  yield* source.statusChanges;
});

/// Live-Mitschnitt der rohen Nachrichten der aktiven Quelle.
final rawLogProvider = NotifierProvider<RawLogNotifier, List<RawMessage>>(RawLogNotifier.new);

class RawLogNotifier extends Notifier<List<RawMessage>> {
  final RawMessageLog log = RawMessageLog();
  bool paused = false;

  @override
  List<RawMessage> build() {
    final source = ref.watch(dartSourceProvider);
    final toFile = ref.watch(settingsProvider.select((s) => s.logRawToFile));
    final sub = source.rawMessages.listen((m) {
      log.add(m);
      if (!paused) state = log.entries;
    });
    if (toFile && source.kind == DartSourceKind.autodartsLocal) {
      unawaited(_startFile());
    }
    ref.onDispose(() {
      unawaited(sub.cancel());
      unawaited(log.stopFileLog());
    });
    return log.entries;
  }

  Future<void> _startFile() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      await log.startFileLog(Directory('${docs.path}${Platform.pathSeparator}DartLab${Platform.pathSeparator}logs'));
      ref.notifyListeners();
    } catch (_) {
      // Ohne Dateisystem (z. B. in Tests) bleibt es beim Speicher-Log.
    }
  }

  void setPaused(bool value) {
    paused = value;
    if (!value) state = log.entries;
  }

  void clear() {
    log.clear();
    state = const [];
  }
}
