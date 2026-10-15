import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/settings/app_settings.dart';
import '../data/screen_client.dart';
import '../domain/screen_state.dart';

/// Verbindungsstand des zweiten Bildschirms.
enum ViewerStatus {
  /// Adresse oder Code des PCs fehlen (Optionen › Sync im Heimnetz).
  notConfigured,
  connecting,
  connected,

  /// Verbindung weg oder nie zustande gekommen; neuer Versuch läuft.
  lost,
  wrongKey,
  notDartLab,
  hubTooOld,
}

@immutable
class ViewerState {
  const ViewerState({required this.status, this.screen, this.host = '', this.everConnected = false});

  final ViewerStatus status;

  /// Zuletzt empfangener Stand (bleibt bei Verbindungsverlust stehen).
  final ScreenState? screen;
  final String host;

  /// War seit dem Öffnen schon einmal verbunden.
  final bool everConnected;

  ViewerState copyWith({ViewerStatus? status, ScreenState? screen}) =>
      ViewerState(status: status ?? this.status, screen: screen ?? this.screen, host: host, everConnected: everConnected || status == ViewerStatus.connected);
}

/// Wie der Viewer sich verbindet; in Tests ersetzbar.
final screenConnectorProvider = Provider<ScreenConnector>((ref) => connectScreen);

/// Bildschirm wach halten, solange der zweite Bildschirm offen ist.
abstract class ScreenWakelock {
  Future<void> set(bool on);
}

class _PluginWakelock implements ScreenWakelock {
  const _PluginWakelock();

  @override
  Future<void> set(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object catch (e) {
      // Ohne Plugin (Tests, alte Plattform) geht der Bildschirm halt aus.
      debugPrint('Wakelock nicht verfügbar: $e');
    }
  }
}

final screenWakelockProvider = Provider<ScreenWakelock>((ref) => const _PluginWakelock());

/// Verbindet den zweiten Bildschirm mit dem Hub und hält die Verbindung:
/// bricht sie ab, versucht er es nach 1, 2, 4 und dann alle 5 Sekunden neu
/// (bei falschem Code alle 10 Sekunden, falls der Code am PC geändert wird).
class ScreenViewerController extends Notifier<ViewerState> {
  /// Wartezeiten zwischen den Versuchen. In Tests überschreibbar.
  static List<Duration> backoff = const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 5),
  ];
  static Duration slowRetry = const Duration(seconds: 10);

  ScreenLink? _link;
  StreamSubscription<ScreenState>? _sub;
  Timer? _retry;
  int _attempts = 0;
  bool _disposed = false;
  int _generation = 0;

  @override
  ViewerState build() {
    final (host, port, key) = ref.watch(settingsProvider.select((s) => (s.syncHost.trim(), s.syncPort, s.syncKey.trim())));
    _disposed = false;
    _attempts = 0;
    ref.onDispose(_teardown);
    if (host.isEmpty || key.isEmpty) return ViewerState(status: ViewerStatus.notConfigured, host: host);
    Future.microtask(() => _connect(host, port, key));
    return ViewerState(status: ViewerStatus.connecting, host: host);
  }

  void _teardown() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    unawaited(_sub?.cancel());
    final link = _link;
    _link = null;
    unawaited(link?.close().catchError((_) {}));
  }

  ({String host, int port, String key}) get _target {
    final s = ref.read(settingsProvider);
    return (host: s.syncHost.trim(), port: s.syncPort, key: s.syncKey.trim());
  }

  /// „Jetzt verbinden“: Wartezeit überspringen.
  void retryNow() {
    if (_disposed || state.status == ViewerStatus.notConfigured || state.status == ViewerStatus.connected) return;
    final t = _target;
    _retry?.cancel();
    unawaited(_connect(t.host, t.port, t.key));
  }

  Future<void> _connect(String host, int port, String key) async {
    if (_disposed) return;
    final generation = ++_generation;
    _retry?.cancel();
    if (state.status != ViewerStatus.lost) state = state.copyWith(status: ViewerStatus.connecting);
    try {
      final link = await ref.read(screenConnectorProvider)(host: host, port: port, key: key);
      if (_disposed || generation != _generation) {
        unawaited(link.close().catchError((_) {}));
        return;
      }
      _link = link;
      _attempts = 0;
      state = state.copyWith(status: ViewerStatus.connected);
      _sub = link.states.listen(
        (s) {
          if (!_disposed && generation == _generation) state = state.copyWith(status: ViewerStatus.connected, screen: s);
        },
        onDone: () => _lost(generation),
        onError: (Object _) => _lost(generation),
        cancelOnError: true,
      );
    } on ScreenConnectException catch (e) {
      if (_disposed || generation != _generation) return;
      final status = switch (e.kind) {
        ScreenFailure.unreachable => ViewerStatus.lost,
        ScreenFailure.wrongKey => ViewerStatus.wrongKey,
        ScreenFailure.notDartLab => ViewerStatus.notDartLab,
        ScreenFailure.hubTooOld => ViewerStatus.hubTooOld,
      };
      state = state.copyWith(status: status);
      _schedule(slow: status != ViewerStatus.lost);
    } on Object {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(status: ViewerStatus.lost);
      _schedule();
    }
  }

  void _lost(int generation) {
    if (_disposed || generation != _generation) return;
    _sub = null;
    final link = _link;
    _link = null;
    unawaited(link?.close().catchError((_) {}));
    state = state.copyWith(status: ViewerStatus.lost);
    _schedule();
  }

  void _schedule({bool slow = false}) {
    _retry?.cancel();
    final delay = slow ? slowRetry : backoff[_attempts.clamp(0, backoff.length - 1)];
    _attempts++;
    _retry = Timer(delay, () {
      final t = _target;
      unawaited(_connect(t.host, t.port, t.key));
    });
  }
}

final screenViewerProvider = NotifierProvider.autoDispose<ScreenViewerController, ViewerState>(ScreenViewerController.new);
