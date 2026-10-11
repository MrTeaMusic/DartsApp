import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../data/sync_client.dart';
import '../data/sync_server.dart';
import '../data/sync_store.dart';
import '../domain/sync_role.dart';

/// Zustand des Abgleichs für die Anzeige.
class SyncState {
  const SyncState({
    this.role = SyncRole.off,
    this.syncing = false,
    this.lastSync,
    this.lastReport,
    this.failure,
    this.failureDetail,
    this.hubRunning = false,
    this.hubError,
    this.hubLastReceived,
  });

  final SyncRole role;

  // Client
  final bool syncing;
  final DateTime? lastSync;
  final SyncReport? lastReport;
  final SyncFailure? failure;
  final String? failureDetail;

  // Hub
  final bool hubRunning;
  final String? hubError;
  final DateTime? hubLastReceived;

  SyncState copyWith({
    bool? syncing,
    DateTime? lastSync,
    SyncReport? lastReport,
    SyncFailure? failure,
    String? failureDetail,
    bool clearFailure = false,
    bool? hubRunning,
    String? hubError,
    DateTime? hubLastReceived,
  }) =>
      SyncState(
        role: role,
        syncing: syncing ?? this.syncing,
        lastSync: lastSync ?? this.lastSync,
        lastReport: lastReport ?? this.lastReport,
        failure: clearFailure ? null : failure ?? this.failure,
        failureDetail: clearFailure ? null : failureDetail ?? this.failureDetail,
        hubRunning: hubRunning ?? this.hubRunning,
        hubError: hubError ?? this.hubError,
        hubLastReceived: hubLastReceived ?? this.hubLastReceived,
      );
}

/// Startet je nach Einstellung den Hub oder gleicht als Client automatisch ab:
/// beim Start, beim Zurückkehren in die App, kurz nach jeder Änderung
/// (z. B. Spielende) und zusätzlich alle paar Minuten.
class SyncController extends Notifier<SyncState> {
  /// Abstand für den regelmäßigen Abgleich.
  static Duration interval = const Duration(minutes: 5);

  /// Wartezeit nach einer Änderung, damit mehrere Änderungen in einem
  /// Abgleich landen.
  static Duration debounce = const Duration(seconds: 2);

  SyncServer? _server;
  Timer? _periodic;
  Timer? _debounce;
  StreamSubscription<String>? _changes;
  StreamSubscription<MergeResult>? _received;
  AppLifecycleListener? _lifecycle;
  String? _lastSignature;
  bool _again = false;
  bool _disposed = false;

  ({SyncRole role, String host, int port, String key}) get _config {
    final s = ref.read(settingsProvider);
    return (role: s.syncRole, host: s.syncHost.trim(), port: s.syncPort, key: s.syncKey);
  }

  @override
  SyncState build() {
    final role = ref.watch(settingsProvider.select((s) => s.syncRole));
    // Bei geänderter Adresse oder Code neu aufsetzen.
    ref.watch(settingsProvider.select((s) => (s.syncHost, s.syncPort, s.syncKey)));
    _disposed = false;
    ref.onDispose(_teardown);
    final effective = role == SyncRole.hub && !canBeHub ? SyncRole.off : role;
    switch (effective) {
      case SyncRole.hub:
        Future.microtask(_startHub);
      case SyncRole.client:
        Future.microtask(_startClient);
      case SyncRole.off:
        break;
    }
    return SyncState(role: effective);
  }

  void _teardown() {
    _disposed = true;
    _periodic?.cancel();
    _debounce?.cancel();
    _changes?.cancel();
    _received?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    final server = _server;
    _server = null;
    unawaited(server?.dispose());
  }

  // ------------------------------------------------------------------ Hub

  Future<void> _startHub() async {
    final c = _config;
    if (c.key.isEmpty) {
      // Code beim ersten Start erzeugen; das baut den Controller neu auf.
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(syncKey: newSyncKey()));
      return;
    }
    final server = SyncServer(ref.read(syncStoreProvider), key: c.key);
    try {
      await server.start(port: c.port);
    } on SocketException catch (e) {
      await server.dispose();
      if (!_disposed) state = state.copyWith(hubRunning: false, hubError: e.osError?.message ?? e.message);
      return;
    }
    if (_disposed) {
      await server.dispose();
      return;
    }
    _server = server;
    _received = server.merged.listen((_) {
      if (!_disposed) state = state.copyWith(hubLastReceived: DateTime.now());
    });
    state = state.copyWith(hubRunning: true);
  }

  // --------------------------------------------------------------- Client

  Future<void> _startClient() async {
    if (_disposed) return;
    final store = ref.read(syncStoreProvider);
    _periodic = Timer.periodic(interval, (_) => syncNow());
    _lifecycle = AppLifecycleListener(onResume: syncNow);
    _changes = store.watchSignature().listen((sig) {
      if (sig == _lastSignature) return;
      _debounce?.cancel();
      _debounce = Timer(debounce, syncNow);
    });
    await syncNow();
  }

  /// Gleicht sofort ab (Knopf in den Optionen). Läuft schon ein Abgleich,
  /// folgt direkt danach noch einer.
  Future<void> syncNow() async {
    final c = _config;
    if (_disposed || state.role != SyncRole.client) return;
    if (c.host.isEmpty || c.key.isEmpty) return;
    if (state.syncing) {
      _again = true;
      return;
    }
    _debounce?.cancel();
    state = state.copyWith(syncing: true);
    final store = ref.read(syncStoreProvider);
    try {
      final report = await SyncClient(store, host: c.host, port: c.port, key: c.key).sync();
      _lastSignature = await store.signature();
      if (_disposed) return;
      state = state.copyWith(syncing: false, lastSync: DateTime.now(), lastReport: report, clearFailure: true);
    } on SyncException catch (e) {
      if (_disposed) return;
      state = state.copyWith(syncing: false, failure: e.kind, failureDetail: e.detail);
    } on Exception catch (e) {
      if (_disposed) return;
      state = state.copyWith(syncing: false, failure: SyncFailure.server, failureDetail: '$e');
    }
    if (_again && !_disposed) {
      _again = false;
      await syncNow();
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
