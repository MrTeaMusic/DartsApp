import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/lite.dart';
import '../../../core/settings/app_settings.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/autodarts_import_repository.dart';
import '../data/autodarts_import_service.dart';
import '../data/autodarts_receiver.dart';
import '../domain/imported_match.dart';

/// Neuer sechsstelliger Code für den Empfänger.
String newImportKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

/// Nur Desktop-Apps (Windows, macOS) können den Empfänger starten; Linux nur
/// zum Entwickeln. Auf iOS/Android gibt es ihn nicht (dort bleibt der
/// JSON-Import von Hand). In Tests überschreibbar.
final importReceiverSupportedProvider = Provider<bool>((ref) {
  if (ref.watch(liteProvider)) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
    _ => false,
  };
});

/// Warum der Empfänger nicht läuft.
enum ReceiverProblem { portBusy, other }

/// Der letzte erfolgreiche Import.
class LastImport {
  const LastImport({required this.opponent, required this.at, required this.legs, this.replaced = false, this.overlap = false});

  final String opponent;
  final DateTime at;

  /// „3:2“ aus Sicht des Spielers.
  final String legs;
  final bool replaced;

  /// Überschneidet sich mit einer Live-Aufzeichnung (Darts zählen doppelt).
  final bool overlap;
}

/// Ein lesbares Match, bei dem noch unklar ist, wer man selbst ist.
class PendingImport {
  const PendingImport({required this.match, required this.origin});

  final ImportedMatch match;
  final String origin;
}

@immutable
class ImportState {
  const ImportState({
    this.running = false,
    this.port,
    this.problem,
    this.problemDetail,
    this.last,
    this.pending = const [],
  });

  final bool running;
  final int? port;
  final ReceiverProblem? problem;
  final String? problemDetail;
  final LastImport? last;
  final List<PendingImport> pending;

  ImportState copyWith({
    bool? running,
    int? port,
    ReceiverProblem? problem,
    String? problemDetail,
    bool clearProblem = false,
    LastImport? last,
    List<PendingImport>? pending,
  }) =>
      ImportState(
        running: running ?? this.running,
        port: port ?? this.port,
        problem: clearProblem ? null : problem ?? this.problem,
        problemDetail: clearProblem ? null : problemDetail ?? this.problemDetail,
        last: last ?? this.last,
        pending: pending ?? this.pending,
      );
}

final autodartsImportRepositoryProvider =
    Provider<AutodartsImportRepository>((ref) => AutodartsImportRepository(ref.watch(appDatabaseProvider)));

/// Liest, erkennt und speichert Matches. Der Name des eigenen Spielers kommt
/// aus den Einstellungen; Empfänger und Dialog nutzen denselben Service.
final autodartsImportServiceProvider = Provider<AutodartsImportService>((ref) {
  return AutodartsImportService(
    repository: ref.watch(autodartsImportRepositoryProvider),
    playerId: () => ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider)),
    myName: () => ref.read(settingsProvider).autodartsMyName,
    rememberName: (name) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(autodartsMyName: name)),
  );
});

/// Startet je nach Einstellung den Empfänger für das Browser-Skript.
///
/// Läuft nur in der Desktop-App, nie in Lite, und nur wenn der Schalter in
/// den Optionen an ist (Standard aus). Hängt weder an der Hub-Rolle noch am
/// Sync-Server.
final autodartsImportControllerProvider = NotifierProvider<AutodartsImportController, ImportState>(AutodartsImportController.new);

class AutodartsImportController extends Notifier<ImportState> {
  AutodartsReceiver? _receiver;
  bool _disposed = false;

  @override
  ImportState build() {
    _disposed = false;
    final supported = ref.watch(importReceiverSupportedProvider);
    final s = ref.watch(settingsProvider.select((x) => (x.autodartsImportEnabled, x.autodartsImportPort, x.autodartsImportKey)));
    ref.onDispose(() {
      _disposed = true;
      final r = _receiver;
      _receiver = null;
      unawaited(r?.stop());
    });
    final (enabled, port, key) = s;
    if (!supported || !enabled) return const ImportState();
    if (key.isEmpty) {
      // Code beim ersten Einschalten erzeugen; das baut den Controller neu auf.
      Future.microtask(() => ref.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsImportKey: newImportKey())));
      return const ImportState();
    }
    Future.microtask(() => _start(port, key));
    return const ImportState();
  }

  Future<void> _start(int port, String key) async {
    if (_disposed) return;
    final receiver = AutodartsReceiver(key: key, handler: _onReceive);
    try {
      await receiver.start(port: port);
    } on SocketException catch (e) {
      await receiver.stop();
      if (!_disposed) {
        state = state.copyWith(
          running: false,
          problem: e.osError == null || _isBusy(e) ? ReceiverProblem.portBusy : ReceiverProblem.other,
          problemDetail: e.osError?.message ?? e.message,
        );
      }
      return;
    }
    if (_disposed) {
      await receiver.stop();
      return;
    }
    _receiver = receiver;
    state = state.copyWith(running: true, port: receiver.port, clearProblem: true);
  }

  bool _isBusy(SocketException e) {
    final code = e.osError?.errorCode;
    // Linux/macOS: EADDRINUSE 98/48, Windows: WSAEADDRINUSE 10048, Zugriff verweigert 10013.
    // -1 meldet Dart, wenn derselbe Prozess den Port schon hält („shared flag“).
    return code == 98 || code == 48 || code == 10048 || code == 10013 || (code == -1 && '${e.osError?.message}'.contains('shared'));
  }

  Future<ImportReply> _onReceive(Object? json, {String? id}) async {
    final reply = await ref.read(autodartsImportServiceProvider).importJson(json, externalId: id, origin: 'browserScript');
    _record(reply, origin: 'browserScript');
    return reply;
  }

  /// Hält das Ergebnis eines Imports fest (Status in den Optionen, offene
  /// Frage „Welcher Spieler bist du?“).
  void _record(ImportReply reply, {required String origin}) {
    if (_disposed) return;
    switch (reply.status) {
      case ImportStatus.imported:
        final plan = reply.plan!;
        state = state.copyWith(
          last: LastImport(
            opponent: plan.opponent.name,
            at: DateTime.now(),
            legs: '${plan.legsMe}:${plan.legsOpponent}',
            replaced: reply.replaced,
            overlap: reply.overlapStartedAt != null,
          ),
          pending: [for (final p in state.pending) if (p.match.id != reply.id) p],
        );
      case ImportStatus.pending:
        final match = reply.match!;
        if (state.pending.any((p) => p.match.id == match.id)) return;
        state = state.copyWith(pending: [...state.pending, PendingImport(match: match, origin: origin)]);
      case ImportStatus.duplicate || ImportStatus.ignored:
        break;
    }
  }

  /// Antwort auf „Welcher Spieler bist du?“: importiert das wartende Match
  /// und merkt sich den Namen.
  Future<ImportReply> resolve(PendingImport pending, int me) async {
    final reply = await ref.read(autodartsImportServiceProvider).importMatch(pending.match, me: me, origin: pending.origin);
    _record(reply, origin: pending.origin);
    return reply;
  }

  /// Verwirft ein wartendes Match, ohne es zu importieren.
  void dismiss(PendingImport pending) {
    state = state.copyWith(pending: [for (final p in state.pending) if (p != pending) p]);
  }

  /// Hält einen Import aus dem Dialog fest (letzter Import in der Statuszeile).
  void recordManual(ImportReply reply) => _record(reply, origin: 'file');
}
