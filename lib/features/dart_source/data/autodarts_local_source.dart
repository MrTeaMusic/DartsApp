import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/board_control.dart';
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
/// (Board Manager 1 und 2), nicht am echten Board geprüft. Das gilt auch für
/// [restart] und [calibrate]: Am Board Manager 2.0.2 sind sie noch nicht bestätigt.
enum AutodartsCommand {
  start('PUT', '/api/start'),
  stop('PUT', '/api/stop'),
  reset('POST', '/api/reset'),

  /// Board Manager neu starten (Refresh). Kennt eine Version den Pfad nicht,
  /// antwortet sie mit 404/405; dann nimmt [AutodartsLocalSource.run] [reset].
  restart('POST', '/api/restart'),

  /// Automatische Kalibrierung starten. Ein POST auf diesen Pfad, kein Abruf
  /// von `/api/config` (dort steht der API-Schlüssel des Boards).
  calibrate('POST', '/api/config/calibration/auto');

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
class AutodartsLocalSource implements DartSource, BoardControl {
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
  final _runningCtrl = StreamController<bool?>.broadcast();

  bool? _boardRunning;
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
    await _runningCtrl.close();
  }

  int _listenOnlyHolds = 0;

  /// Nur mithören: Solange ein Halter aktiv ist, verweigert [send] jeden
  /// Befehl, der nicht ausdrücklich vom Nutzer kommt. Autodarts Live nutzt das,
  /// weil ein Start/Stop/Reset ein laufendes Online-Match auf play.autodarts.io
  /// stören würde.
  @override
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

  @override
  String get boardAddress => '$host:$port';

  @override
  bool? get boardRunning => _boardRunning;

  @override
  Stream<bool?> get boardRunningChanges => _runningCtrl.stream;

  void _setRunning(bool? value) {
    if (value == _boardRunning) return;
    _boardRunning = value;
    if (!_disposed) _runningCtrl.add(value);
  }

  /// Schickt einen Befehl an den Board Manager. Im Modus [listenOnly] geht er
  /// nur raus, wenn [userInitiated] gesetzt ist, also ein Knopfdruck des
  /// Nutzers dahintersteckt. Automatische Aufrufer lassen es auf `false`.
  Future<bool> send(AutodartsCommand command, {bool userInitiated = false}) async =>
      (await sendCommand(command, userInitiated: userInitiated)).ok;

  /// Wie [send], liefert aber den HTTP-Status bzw. den Fehlertext. Vom Body
  /// der Antwort wird nichts gelesen oder geloggt, nur der Statuscode.
  Future<BoardCommandResult> sendCommand(AutodartsCommand command, {bool userInitiated = false}) async {
    if (listenOnly) {
      if (!userInitiated) {
        _info('Befehl ${command.name} nicht gesendet: Autodarts Live hört nur mit');
        return const BoardCommandResult.blocked();
      }
      _info('Befehl ${command.name} auf ausdrücklichen Wunsch trotz „nur mithören“');
    }
    final uri = Uri(scheme: 'http', host: host, port: port, path: command.path);
    _log('http ${command.method} ${command.path}', '', incoming: false);
    try {
      final req = http.Request(command.method, uri);
      final res = await _http.send(req).timeout(connectTimeout);
      // Body wird verworfen: ungelesen, ungeloggt.
      await res.stream.drain<void>().timeout(connectTimeout);
      _log('http ${res.statusCode} ${command.path}', '');
      return BoardCommandResult(statusCode: res.statusCode, path: command.path);
    } catch (e) {
      final text = _short(e);
      _info('Befehl ${command.name} fehlgeschlagen: $text');
      return BoardCommandResult(error: text, path: command.path);
    }
  }

  static String _short(Object e) {
    if (e is TimeoutException) return 'Zeitüberschreitung';
    final text = '$e'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  @override
  Future<BoardCommandResult> run(BoardAction action, {bool userInitiated = false}) async {
    switch (action) {
      case BoardAction.recalibrate:
        return sendCommand(AutodartsCommand.calibrate, userInitiated: userInitiated);
      case BoardAction.stop:
        final r = await sendCommand(AutodartsCommand.stop, userInitiated: userInitiated);
        if (r.ok) _setRunning(false);
        return r;
      case BoardAction.start:
        final r = await sendCommand(AutodartsCommand.start, userInitiated: userInitiated);
        if (r.ok) _setRunning(true);
        return r;
      case BoardAction.refresh:
        final first = await sendCommand(AutodartsCommand.restart, userInitiated: userInitiated);
        // Nur ein „Pfad unbekannt“ löst den Rückfall aus, kein Verbindungsfehler.
        if (first.statusCode != 404 && first.statusCode != 405) return first;
        final second = await sendCommand(AutodartsCommand.reset, userInitiated: userInitiated);
        return BoardCommandResult(
          statusCode: second.statusCode,
          error: second.error,
          path: second.path,
          fellBackFrom: first.path,
          fallbackStatusCode: first.statusCode,
        );
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
    final running = state['running'];
    if (running is bool) _setRunning(running);
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
