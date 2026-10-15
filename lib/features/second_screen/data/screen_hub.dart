import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/screen_state.dart';
import 'screen_page.dart';

/// Pfade des zweiten Bildschirms auf dem Hub.
abstract final class ScreenPaths {
  /// Browser-Seite (nur lesen).
  static const page = '/screen';

  /// WebSocket mit den Ständen.
  static const socket = '/screen/ws';

  static bool matches(String path) => path == page || path == socket;
}

/// Verteilt den Spielstand an die zweiten Bildschirme im Heimnetz.
///
/// Läuft im [SyncServer] auf demselben Port. Jeder Viewer hält eine
/// WebSocket-Verbindung; der Hub schickt bei jeder Änderung den kompletten
/// (kleinen) Stand als JSON-Text. Viewer schicken nichts: jede Nachricht
/// eines Viewers beendet seine Verbindung.
///
/// Damit das Spiel am PC nicht langsamer wird:
/// * Ohne Viewer passiert nichts: [markDirty] kehrt sofort zurück, und
///   über [viewerCount] meldet der Hub, wann jemand zuschaut (dann erst
///   hört der Feed überhaupt auf die Spiele).
/// * Änderungen werden gesammelt: höchstens alle [throttle] wird ein Stand
///   gebaut und nur verschickt, wenn er sich geändert hat.
/// * Alle [heartbeat] wird zusätzlich geprüft (fängt Änderungen ab, die der
///   Feed nicht meldet, z. B. ein umbenanntes Profil).
class ScreenHub {
  ScreenHub({
    required this.snapshot,
    this.throttle = const Duration(milliseconds: 80),
    this.heartbeat = const Duration(seconds: 2),
    this.pingInterval = const Duration(seconds: 5),
    this.maxViewers = 8,
  });

  /// Baut den aktuellen Stand. Wird nur mit Viewern aufgerufen.
  final ScreenState Function() snapshot;
  final Duration throttle;
  final Duration heartbeat;

  /// WebSocket-Ping, damit tote Verbindungen (Tablet aus, WLAN weg)
  /// erkannt und freigegeben werden.
  final Duration pingInterval;
  final int maxViewers;

  final Set<WebSocket> _viewers = {};
  final _count = StreamController<int>.broadcast();
  Timer? _pending;
  Timer? _beat;
  String? _last;
  bool _closed = false;

  /// Zahl der verbundenen Viewer (für die Anzeige am Hub und den Feed).
  int get viewers => _viewers.length;
  Stream<int> get viewerCount => _count.stream;

  /// Der Stand hat sich (vielleicht) geändert.
  void markDirty() {
    if (_viewers.isEmpty || _pending != null || _closed) return;
    _pending = Timer(throttle, _flush);
  }

  void _flush() {
    _pending = null;
    if (_viewers.isEmpty) return;
    final text = _encode();
    if (text == _last) return;
    _last = text;
    for (final v in [..._viewers]) {
      v.add(text);
    }
  }

  String _encode() {
    ScreenState state;
    try {
      state = snapshot();
    } catch (_) {
      // Ein Fehler beim Zusammenstellen darf das Spiel nicht stören.
      state = ScreenState.idle;
    }
    return jsonEncode({'type': 'state', 'state': state.toJson()});
  }

  /// Bearbeitet eine Anfrage an [ScreenPaths]. [authorized]: Code stimmt
  /// (Header oder `?key=`).
  Future<void> handle(HttpRequest req, {required bool authorized}) async {
    final res = req.response;
    if (req.method != 'GET') return _plain(res, HttpStatus.methodNotAllowed, 'Nur GET');
    if (req.uri.path == ScreenPaths.page) {
      res.statusCode = authorized ? HttpStatus.ok : HttpStatus.unauthorized;
      res.headers
        ..contentType = ContentType.html
        ..set('Cache-Control', 'no-store')
        ..set('Content-Security-Policy', screenPageCsp)
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Referrer-Policy', 'no-referrer');
      res.write(authorized ? screenPageHtml : screenLoginHtml);
      return res.close();
    }
    if (!authorized) return _plain(res, HttpStatus.unauthorized, 'Falscher Code');
    if (!WebSocketTransformer.isUpgradeRequest(req)) return _plain(res, HttpStatus.badRequest, 'WebSocket erwartet');
    if (_viewers.length >= maxViewers || _closed) return _plain(res, HttpStatus.serviceUnavailable, 'Zu viele Bildschirme');
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(req);
    } on Object {
      return;
    }
    socket.pingInterval = pingInterval;
    _viewers.add(socket);
    _changed();
    // Neuer Viewer bekommt sofort den aktuellen Stand.
    final text = _encode();
    _last = text;
    socket.add(text);
    void drop() {
      if (_viewers.remove(socket)) _changed();
    }

    socket.listen(
      (_) {
        // Nur lesen: wer etwas schickt, fliegt raus.
        drop();
        unawaited(socket.close(WebSocketStatus.policyViolation));
      },
      onDone: drop,
      onError: (_) => drop(),
      cancelOnError: true,
    );
  }

  void _changed() {
    if (_viewers.isEmpty) {
      _beat?.cancel();
      _beat = null;
      _pending?.cancel();
      _pending = null;
      _last = null;
    } else {
      _beat ??= Timer.periodic(heartbeat, (_) => markDirty());
    }
    if (!_count.isClosed) _count.add(_viewers.length);
  }

  Future<void> close() async {
    _closed = true;
    _pending?.cancel();
    _beat?.cancel();
    final all = [..._viewers];
    _viewers.clear();
    for (final v in all) {
      unawaited(v.close(WebSocketStatus.goingAway).catchError((_) {}));
    }
    if (!_count.isClosed) {
      _count.add(0);
      await _count.close();
    }
  }

  static Future<void> _plain(HttpResponse res, int status, String message) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({'error': message}));
    await res.close();
  }
}
