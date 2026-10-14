import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/coordinate_calibration.dart';
import '../domain/dart_event.dart';
import '../domain/dart_source.dart';
import 'autodarts_state_mapper.dart';

typedef WebSocketConnector = Future<WebSocketChannel> Function(Uri uri);

/// Öffnet einen WebSocket und wartet, bis er bereit ist.
Future<WebSocketChannel> defaultWebSocketConnector(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready;
  return channel;
}

/// Befehle an den Board Manager. Pfade laut Home-Assistant-Integration
/// (Board Manager 1 und 2), nicht am echten Board geprüft.
enum AutodartsCommand {
  start('PUT', '/api/start'),
  stop('PUT', '/api/stop'),
  reset('POST', '/api/reset');

  const AutodartsCommand(this.method, this.path);
  final String method;
  final String path;
}

/// Verbindet sich mit dem lokalen Autodarts Board Manager.
///
/// 1. WebSocket `ws://host:port/api/events`, Nachrichten der Form
///    `{"type": "state", "data": {...}}`.
/// 2. Fällt der WebSocket aus, HTTP-Polling auf `GET /api/state`.
/// 3. Ist beides nicht erreichbar, neuer Versuch mit wachsender Wartezeit.
///
/// Das Protokoll ist nicht offiziell dokumentiert und noch nicht am echten
/// Board getestet. Jede eingehende Nachricht geht roh an [rawMessages].
class AutodartsLocalSource implements DartSource {
  AutodartsLocalSource({
    required this.host,
    this.port = 3180,
    http.Client? httpClient,
    WebSocketConnector? connector,
    this.pollInterval = const Duration(milliseconds: 500),
    this.connectTimeout = const Duration(seconds: 5),
    this.maxBackoff = const Duration(seconds: 30),
    DateTime Function()? clock,
    math.Random? random,
    CoordinateCalibration calibration = CoordinateCalibration.identity,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _connector = connector ?? defaultWebSocketConnector,
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random(),
        _mapper = AutodartsStateMapper(clock: clock, calibration: calibration);

  final String host;
  final int port;
  final Duration pollInterval;
  final Duration connectTimeout;
  final Duration maxBackoff;

  final http.Client _http;
  final bool _ownsHttp;
  final WebSocketConnector _connector;
  final DateTime Function() _clock;
  final math.Random _random;
  final AutodartsStateMapper _mapper;

  final _events = StreamController<DartEvent>.broadcast();
  final _statusCtrl = StreamController<SourceStatus>.broadcast();
  final _raw = StreamController<RawMessage>.broadcast();

  SourceStatus _status = SourceStatus.idle;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pollTimer;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _running = false;
  bool _disposed = false;
  bool _pollBusy = false;

  Uri get webSocketUri => Uri(scheme: 'ws', host: host, port: port, path: '/api/events');
  Uri get stateUri => Uri(scheme: 'http', host: host, port: port, path: '/api/state');

  @override
  DartSourceKind get kind => DartSourceKind.autodartsLocal;

  @override
  bool get providesCoordinates => true;

  @override
  Stream<DartEvent> get events => _events.stream;

  @override
  Stream<SourceStatus> get statusChanges => _statusCtrl.stream;

  @override
  SourceStatus get status => _status;

  @override
  Stream<RawMessage> get rawMessages => _raw.stream;

  /// Hinweise des Mappers zu nicht verstandenen Daten.
  List<String> get mappingWarnings => List.unmodifiable(_mapper.warnings);

  @override
  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    _attempt = 0;
    await _connect();
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _teardown();
    _setStatus(SourceStatus.idle);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    if (_ownsHttp) _http.close();
    await _events.close();
    await _statusCtrl.close();
    await _raw.close();
  }

  int _listenOnlyHolds = 0;

  /// Nur mithören: Solange ein Halter aktiv ist, verweigert [send] jeden
  /// Befehl. Autodarts Live nutzt das, weil ein Start/Stop/Reset ein
  /// laufendes Online-Match auf play.autodarts.io stören würde.
  bool get listenOnly => _listenOnlyHolds > 0;

  /// Schaltet [listenOnly] ein. Die zurückgegebene Funktion gibt den Halter
  /// wieder frei (mehrfacher Aufruf schadet nicht).
  void Function() holdListenOnly() {
    _listenOnlyHolds++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _listenOnlyHolds--;
    };
  }

  /// Schickt einen Befehl an den Board Manager (nicht im Modus [listenOnly]).
  Future<bool> send(AutodartsCommand command) async {
    if (listenOnly) {
      _info('Befehl ${command.name} nicht gesendet: Autodarts Live hört nur mit');
      return false;
    }
    final uri = Uri(scheme: 'http', host: host, port: port, path: command.path);
    _log('http ${command.method} ${command.path}', '', incoming: false);
    try {
      final req = http.Request(command.method, uri);
      final res = await _http.send(req).timeout(connectTimeout);
      final body = await res.stream.bytesToString();
      _log('http ${res.statusCode} ${command.path}', body);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      _info('Befehl ${command.name} fehlgeschlagen: $e');
      return false;
    }
  }

  Future<void> _connect() async {
    if (!_running) return;
    _setStatus(const SourceStatus(SourcePhase.connecting));
    _mapper.resetBaseline();

    // 1. WebSocket
    try {
      _info('Verbinde WebSocket $webSocketUri');
      final channel = await _connector(webSocketUri).timeout(connectTimeout);
      if (!_running) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _attempt = 0;
      _setStatus(const SourceStatus(SourcePhase.connected));
      _info('WebSocket verbunden');
      _wsSub = channel.stream.listen(
        _onWsMessage,
        onError: (Object e) => _onLost('WebSocket-Fehler: $e'),
        onDone: () => _onLost('WebSocket geschlossen (${channel.closeCode ?? '-'})'),
        cancelOnError: true,
      );
      return;
    } catch (e) {
      _info('WebSocket nicht verfügbar: $e');
    }

    // 2. HTTP-Polling
    if (await _pollOnce()) {
      if (!_running) return;
      _attempt = 0;
      _setStatus(const SourceStatus(SourcePhase.polling,
          message: 'Kein WebSocket, nutze HTTP-Polling'));
      _pollTimer = Timer.periodic(pollInterval, (_) => _pollTick());
      return;
    }

    // 3. Später erneut versuchen
    _scheduleRetry('Board Manager unter $host:$port nicht erreichbar');
  }

  void _onWsMessage(dynamic message) {
    final text = message is String ? message : utf8.decode(message as List<int>);
    _log('ws', text);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final map = decoded.cast<String, Object?>();
    final type = map['type'];
    final data = map['data'];
    if (type == 'state' && data is Map) {
      _apply(data.cast<String, Object?>());
    } else if (type == null && (map.containsKey('throws') || map.containsKey('numThrows'))) {
      // Falls der Zustand ohne Umschlag kommt.
      _apply(map);
    }
  }

  Future<void> _pollTick() async {
    if (_pollBusy) return;
    _pollBusy = true;
    final ok = await _pollOnce();
    _pollBusy = false;
    if (!ok && _running && _pollTimer != null) {
      _onLost('HTTP-Polling fehlgeschlagen');
    }
  }

  Future<bool> _pollOnce() async {
    try {
      final res = await _http.get(stateUri).timeout(connectTimeout);
      _log('http GET /api/state ${res.statusCode}', res.body);
      if (res.statusCode != 200) return false;
      final decoded = jsonDecode(res.body);
      if (decoded is Map) _apply(decoded.cast<String, Object?>());
      return true;
    } catch (e) {
      _info('HTTP /api/state fehlgeschlagen: $e');
      return false;
    }
  }

  void _apply(Map<String, Object?> state) {
    final before = _mapper.warnings.length;
    for (final event in _mapper.update(state)) {
      if (!_disposed) _events.add(event);
    }
    for (final w in _mapper.warnings.skip(before)) {
      _info('Mapping: $w');
    }
  }

  void _onLost(String reason) {
    if (!_running) return;
    _info(reason);
    unawaited(_teardown().then((_) => _scheduleRetry(reason)));
  }

  void _scheduleRetry(String reason) {
    if (!_running) return;
    final delay = backoffFor(_attempt++);
    final next = _clock().add(delay);
    _setStatus(SourceStatus(SourcePhase.reconnecting, message: reason, nextRetry: next));
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_connect()));
  }

  /// Wartezeit vor Versuch Nummer [attempt]: 1 s, 2 s, 4 s … bis [maxBackoff],
  /// plus bis zu 20 % Zufall, damit mehrere Geräte nicht gleichzeitig anklopfen.
  Duration backoffFor(int attempt) {
    final baseMs = math.min(1000 * math.pow(2, attempt).toInt(), maxBackoff.inMilliseconds);
    final jitter = (baseMs * 0.2 * _random.nextDouble()).round();
    return Duration(milliseconds: baseMs + jitter);
  }

  Future<void> _teardown() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink.close().timeout(const Duration(seconds: 1));
      } catch (_) {
        // Verbindung ist ohnehin weg.
      }
    }
  }

  void _setStatus(SourceStatus s) {
    if (s == _status) return;
    _status = s;
    if (!_disposed) _statusCtrl.add(s);
  }

  void _log(String channel, String payload, {bool incoming = true}) {
    if (_disposed) return;
    _raw.add(RawMessage(
      timestamp: _clock(),
      channel: channel,
      payload: payload,
      incoming: incoming,
    ));
  }

  void _info(String text) => _log('info', text, incoming: false);
}
