import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../second_screen/domain/screen_state.dart';
import '../../sync/data/cloud_api.dart';
import '../../sync/data/cloud_crypto.dart';
import '../../sync/data/sync_client.dart';
import '../../sync/presentation/sync_controller.dart' show cloudHttpClientProvider;
import '../data/live_packet.dart';

/// Was die Live-Ansicht der Lite-App zeigt.
enum LiveViewStatus {
  /// Erste Abfrage läuft.
  connecting,

  /// Ben spielt: [LiveViewState.screen] ist der Stand.
  playing,

  /// Kein Paket, ein „idle“-Paket oder ein Paket, das älter ist als
  /// [LiveViewerController.staleAfter].
  notPlaying,

  /// Der Cloud-Speicher ist nicht erreichbar; neuer Versuch läuft. Der
  /// letzte Stand bleibt in [LiveViewState.screen].
  lost,

  /// Der Worker kennt `/v1/live` nicht (alte Fassung).
  workerTooOld,

  /// Das Geheimnis passt nicht (Zugang abgelehnt, kein Tresor, Paket nicht lesbar).
  wrongSecret,
}

@immutable
class LiveViewState {
  const LiveViewState({required this.status, this.screen});

  final LiveViewStatus status;

  /// Stand, solange Ben spielt; bei [LiveViewStatus.lost] der letzte.
  final ScreenState? screen;
}

/// Holt Bens Spielstand aus dem Cloud-Speicher (nur lesen).
///
/// Fragt nur ab, solange die Ansicht „aktiv“ ist ([setActive]: Reiter offen
/// und App im Vordergrund). Jede Abfrage nennt die zuletzt gesehene Version
/// (`?since=`); der Server antwortet bei unverändertem Stand mit 304 ohne
/// Inhalt. Takt: alle [pollPlaying], solange Ben spielt, sonst seltener
/// ([pollIdle], nach langer Ruhe [pollIdleSlow]), damit ein vergessen offenes
/// Handy das Tageslimit nicht aufzehrt.
class LiveViewerController extends Notifier<LiveViewState> {
  static Duration pollPlaying = const Duration(seconds: 2);
  static Duration pollIdle = const Duration(seconds: 5);
  static Duration pollIdleSlow = const Duration(seconds: 15);

  /// Nach so langem Nichtspielen wird auf [pollIdleSlow] gewechselt.
  static Duration idleSlowAfter = const Duration(minutes: 10);

  /// Ist das Paket (nach der Uhr des Servers) älter, spielt Ben nicht mehr:
  /// Der Sender schickt beim Spielen alle 20 Sekunden einen Herzschlag.
  static Duration staleAfter = const Duration(seconds: 60);

  /// Wartezeiten nach Verbindungsfehlern; der letzte Wert gilt weiter.
  static List<Duration> lostBackoff = const [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 10)];

  /// Bei altem Worker (Ben kann ihn aktualisieren) und falschem Geheimnis.
  static Duration workerRecheck = const Duration(seconds: 60);
  static Duration wrongSecretRetry = const Duration(seconds: 30);

  Timer? _timer;
  CloudApi? _api;
  CloudKeys? _keys;
  bool _active = false;
  bool _inFlight = false;
  bool _disposed = false;
  bool _helloOk = false;
  int _generation = 0;
  int _lostCount = 0;
  int? _rev;
  ScreenState? _packetState;
  Duration? _age;
  Duration _idleFor = Duration.zero;

  /// Anzahl der Abfragen seit dem Start (für Tests).
  int polls = 0;

  @override
  LiveViewState build() {
    ref.watch(settingsProvider.select((s) => (s.syncCloudUrl, s.syncCloudSecret)));
    _disposed = false;
    _inFlight = false;
    _helloOk = false;
    _lostCount = 0;
    _rev = null;
    _packetState = null;
    _age = null;
    _idleFor = Duration.zero;
    ref.onDispose(_teardown);
    // Neue Adresse oder neues Geheimnis bei offener Ansicht: von vorn.
    if (_active) Future.microtask(_poll);
    return const LiveViewState(status: LiveViewStatus.connecting);
  }

  void _teardown() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _api?.close();
    _api = null;
  }

  /// Reiter offen und App im Vordergrund? Nur dann wird abgefragt.
  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _timer?.cancel();
    _timer = null;
    if (active) {
      _lostCount = 0;
      unawaited(_poll());
    }
  }

  /// „Jetzt verbinden“: Wartezeit überspringen.
  void retryNow() {
    if (_disposed || !_active) return;
    _timer?.cancel();
    _lostCount = 0;
    unawaited(_poll());
  }

  Future<CloudApi?> _client() async {
    if (_api != null) return _api;
    final s = ref.read(settingsProvider);
    final secret = CloudSecret.tryParse(s.syncCloudSecret);
    if (secret == null || CloudApi.tryParseUrl(s.syncCloudUrl) == null) return null;
    final keys = await secret.keys();
    _keys = keys;
    return _api = CloudApi(s.syncCloudUrl, keys.token, client: ref.read(cloudHttpClientProvider)(), timeout: const Duration(seconds: 10));
  }

  Future<void> _poll() async {
    if (!_active || _inFlight || _disposed) return;
    _inFlight = true;
    final generation = _generation;
    polls++;
    var next = pollIdle;
    try {
      final api = await _client();
      if (api == null) {
        _set(const LiveViewState(status: LiveViewStatus.wrongSecret), generation);
        next = wrongSecretRetry;
        return;
      }
      if (!_helloOk) {
        if (!(await api.hello()).hasLive) throw const CloudTooOldException();
        _helloOk = true;
      }
      final reply = await api.getLive(since: _rev);
      if (generation != _generation) return;
      if (reply == null) {
        _rev = null;
        _packetState = null;
        _age = null;
      } else if (reply.notModified) {
        _age = reply.age ?? _age;
      } else {
        final packet = await openLivePacket(_keys!, reply.body!);
        _rev = reply.rev;
        _packetState = packet.state;
        _age = reply.age ?? DateTime.now().difference(packet.sentAt);
      }
      _lostCount = 0;
      final shown = _packetState;
      final playing = shown != null && !shown.isIdle && (_age ?? Duration.zero) < staleAfter;
      _set(playing ? LiveViewState(status: LiveViewStatus.playing, screen: shown) : const LiveViewState(status: LiveViewStatus.notPlaying), generation);
      next = playing ? pollPlaying : (_idleFor >= idleSlowAfter ? pollIdleSlow : pollIdle);
    } on CloudTooOldException {
      _helloOk = false;
      _set(const LiveViewState(status: LiveViewStatus.workerTooOld), generation);
      next = workerRecheck;
    } on CloudDecryptException {
      _set(const LiveViewState(status: LiveViewStatus.wrongSecret), generation);
      next = wrongSecretRetry;
    } on SyncException catch (e) {
      switch (e.kind) {
        case SyncFailure.wrongKey || SyncFailure.noVault || SyncFailure.wrongSecret:
          _set(const LiveViewState(status: LiveViewStatus.wrongSecret), generation);
          next = wrongSecretRetry;
        case SyncFailure.unreachable || SyncFailure.server || SyncFailure.notDartLab:
          next = _lost(generation);
      }
    } on Object {
      next = _lost(generation);
    } finally {
      if (generation == _generation) _inFlight = false;
      if (_active && !_disposed && generation == _generation) {
        _idleFor = state.status == LiveViewStatus.notPlaying ? _idleFor + next : Duration.zero;
        _timer?.cancel();
        _timer = Timer(next, () => unawaited(_poll()));
      }
    }
  }

  Duration _lost(int generation) {
    final wait = lostBackoff[_lostCount.clamp(0, lostBackoff.length - 1)];
    _lostCount++;
    _set(LiveViewState(status: LiveViewStatus.lost, screen: state.status == LiveViewStatus.playing || state.status == LiveViewStatus.lost ? state.screen : null), generation);
    return wait;
  }

  void _set(LiveViewState next, int generation) {
    if (_disposed || generation != _generation) return;
    state = next;
  }
}

final liveViewerProvider = NotifierProvider.autoDispose<LiveViewerController, LiveViewState>(LiveViewerController.new);
