import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../second_screen/domain/screen_state.dart';
import '../../sync/data/cloud_api.dart';
import '../../sync/data/sync_client.dart';
import 'live_sink.dart';

/// Wie es mit dem Senden steht (für die Sync-Karte).
enum LivePushStatus {
  /// Schalter aus oder keine Cloud-Rolle: es passiert nichts.
  off,

  /// Schalter an, aber Adresse oder Geheimnis fehlen oder taugen nicht.
  notConfigured,

  /// Schalter an, der Cloud-Speicher wird gerade geprüft.
  starting,

  /// An und bereit; gesendet wird, sobald ein Spiel läuft.
  waiting,

  /// Der letzte Versuch hat geklappt.
  ok,

  /// Keine Verbindung zum Cloud-Speicher; neuer Versuch läuft.
  unreachable,

  /// Der Worker ist die alte Fassung ohne Live (neu einfügen, siehe `cloud/README.md`).
  workerTooOld,

  /// Der Cloud-Speicher lehnt den Zugang ab.
  wrongKey,

  /// Der Cloud-Speicher meldet einen Fehler (auch Tageslimit); neuer Versuch läuft.
  server,
}

@immutable
class LivePushInfo {
  const LivePushInfo(this.status, {this.lastSent, this.detail});

  final LivePushStatus status;

  /// Wann zuletzt etwas gesendet wurde (Uhr dieses Geräts).
  final DateTime? lastSent;
  final String? detail;

  static const off = LivePushInfo(LivePushStatus.off);

  @override
  bool operator ==(Object other) => other is LivePushInfo && other.status == status && other.lastSent == lastSent && other.detail == detail;

  @override
  int get hashCode => Object.hash(status, lastSent, detail);
}

/// Schickt den Spielstand dieses Geräts an den Cloud-Speicher, damit
/// Zuschauer (die Lite-App) ihn live sehen.
///
/// Der Stand kommt aus derselben Funktion wie beim Hub des zweiten
/// Bildschirms ([snapshot], `ScreenFeed.snapshot`). Damit das Spiel nie
/// langsamer wird und der Gratis-Tarif reicht:
/// * Gesendet wird nur, wenn sich der Stand (als JSON) geändert hat, und
///   höchstens alle [throttle]. Änderungen dazwischen werden gesammelt, der
///   letzte Stand geht danach raus.
/// * Läuft ein Spiel und ändert sich nichts, geht alle [heartbeat] trotzdem
///   ein Paket raus; daran sieht der Zuschauer, dass dieses Gerät noch da
///   ist. Ohne Spiel gibt es keinen Herzschlag.
/// * Endet ein Spiel, geht einmal ein „idle“-Stand raus; ohne vorheriges
///   Spiel wird nichts gesendet.
/// * Alles läuft asynchron und fängt jeden Fehler: Kein Netz, ein alter
///   Worker oder ein Tageslimit lassen das Spiel unberührt. Der Pusher
///   versucht es mit wachsendem Abstand ([backoff]) wieder und meldet den
///   Zustand über [onStatus].
class LivePusher {
  LivePusher({
    required this.snapshot,
    required this.sink,
    this.onStatus,
    this.throttle = const Duration(milliseconds: 1500),
    this.heartbeat = const Duration(seconds: 20),
    this.recheck = const Duration(seconds: 5),
    this.backoff = const [Duration(seconds: 3), Duration(seconds: 6), Duration(seconds: 12), Duration(seconds: 30), Duration(seconds: 60)],
    this.oldWorkerRetry = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Baut den aktuellen Stand (wie beim Hub des zweiten Bildschirms).
  final ScreenState Function() snapshot;
  final LiveSink sink;
  final void Function(LivePushInfo info)? onStatus;
  final Duration throttle;
  final Duration heartbeat;

  /// Abstand, in dem der Stand auch ohne Meldung der Spiele geprüft wird
  /// (lokal, kostet keine Anfrage).
  final Duration recheck;

  /// Wartezeiten nach Fehlern; der letzte Wert gilt von da an.
  final List<Duration> backoff;

  /// Abstand, in dem ein alter Worker erneut geprüft wird (Ben kann ihn
  /// aktualisieren, ohne die App neu zu starten).
  final Duration oldWorkerRetry;
  final DateTime Function() _now;

  Timer? _cooling;
  Timer? _beat;
  Timer? _recheck;
  bool _started = false;
  bool _stopped = false;
  bool _inFlight = false;
  bool _dirty = false;
  bool _beatDue = false;
  bool _checked = false;
  int _failures = 0;

  /// Zuletzt erfolgreich gesendeter Stand (JSON) und ob er „idle“ war.
  String? _lastJson;
  bool _lastIdle = true;
  DateTime? _lastSentAt;
  LivePushInfo _info = const LivePushInfo(LivePushStatus.starting);

  /// Wie oft gesendet wurde (für Tests und Anzeige).
  int sent = 0;

  LivePushInfo get info => _info;

  /// Fängt an. Die erste Anfrage prüft, ob der Cloud-Speicher Live kennt.
  void start() {
    if (_started || _stopped) return;
    _started = true;
    _recheck = Timer.periodic(recheck, (_) => markDirty());
    markDirty();
  }

  /// Der Stand hat sich (vielleicht) geändert. Kehrt sofort zurück.
  void markDirty() {
    if (!_started || _stopped) return;
    _dirty = true;
    _pump();
  }

  void _pump() {
    if (_stopped || _inFlight || _cooling != null || !_dirty) return;
    _dirty = false;
    unawaited(_run());
  }

  void _cool(Duration d) {
    _cooling?.cancel();
    _cooling = Timer(d, () {
      _cooling = null;
      _pump();
    });
  }

  void _report(LivePushStatus status, {String? detail}) {
    if (_stopped) return;
    final info = LivePushInfo(status, lastSent: _lastSentAt, detail: detail);
    if (info == _info) return;
    _info = info;
    onStatus?.call(info);
  }

  Future<void> _run() async {
    _inFlight = true;
    try {
      if (!_checked) {
        await sink.check();
        _checked = true;
        if (_stopped) return;
        _report(_lastSentAt == null ? LivePushStatus.waiting : LivePushStatus.ok);
      }
      final ScreenState state;
      try {
        state = snapshot();
      } on Object {
        // Ein Fehler beim Zusammenstellen darf das Spiel nicht stören; beim
        // nächsten Mal wird es erneut versucht.
        return;
      }
      final json = jsonEncode(state.toJson());
      final idle = state.isIdle;
      // Ohne Spiel gibt es nichts zu senden, außer dem Ende eines Spiels.
      final due = idle ? (_lastJson != null && !_lastIdle) : (json != _lastJson || _beatDue);
      if (!due) return;
      // Ab hier zählt es als Sendeversuch: höchstens einer je [throttle].
      _cool(throttle);
      await sink.send(state);
      if (_stopped) return;
      sent++;
      _lastJson = json;
      _lastIdle = idle;
      _lastSentAt = _now();
      _failures = 0;
      _beatDue = false;
      _beat?.cancel();
      _beat = idle
          ? null
          : Timer(heartbeat, () {
              _beatDue = true;
              markDirty();
            });
      _report(LivePushStatus.ok);
    } on CloudTooOldException {
      _failed(LivePushStatus.workerTooOld, oldWorkerRetry);
    } on SyncException catch (e) {
      switch (e.kind) {
        case SyncFailure.wrongKey || SyncFailure.noVault || SyncFailure.wrongSecret:
          _failed(LivePushStatus.wrongKey, backoff.last);
        case SyncFailure.unreachable:
          _failed(LivePushStatus.unreachable, _nextBackoff());
        case SyncFailure.notDartLab:
          _failed(LivePushStatus.server, _nextBackoff(), detail: 'Adresse');
        case SyncFailure.server:
          _failed(LivePushStatus.server, _nextBackoff(), detail: e.detail);
      }
    } on Object catch (e) {
      _failed(LivePushStatus.server, _nextBackoff(), detail: '$e');
    } finally {
      _inFlight = false;
      _pump();
    }
  }

  Duration _nextBackoff() => backoff[_failures.clamp(0, backoff.length - 1)];

  void _failed(LivePushStatus status, Duration retryIn, {String? detail}) {
    if (_stopped) return;
    _failures++;
    // Der nächste Durchlauf prüft den Cloud-Speicher zuerst wieder.
    _checked = false;
    _report(status, detail: detail);
    // Nach der Wartezeit wird mit dem dann aktuellen Stand neu versucht.
    _dirty = true;
    _cool(retryIn);
  }

  /// Hört auf. Mit [sendIdle] bekommt der Zuschauer noch einen „idle“-Stand,
  /// wenn gerade ein Spiel gezeigt wird (z. B. wenn der Schalter ausgeht).
  /// Der Versuch läuft im Hintergrund und gibt schnell auf.
  void stop({bool sendIdle = false}) {
    if (_stopped) return;
    _stopped = true;
    _cooling?.cancel();
    _beat?.cancel();
    _recheck?.cancel();
    _cooling = _beat = _recheck = null;
    if (sendIdle && _started && _lastJson != null && !_lastIdle) {
      unawaited(() async {
        try {
          await sink.send(ScreenState.idle).timeout(const Duration(seconds: 5));
        } on Object {
          // Egal: Der Zuschauer merkt nach einer Minute ohnehin, dass nichts mehr kommt.
        } finally {
          sink.close();
        }
      }());
    } else {
      sink.close();
    }
  }
}
