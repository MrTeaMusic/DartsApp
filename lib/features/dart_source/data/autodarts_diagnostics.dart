import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'autodarts_local_source.dart';

/// Ergebnis eines Prüfschritts.
enum CheckResult { ok, warning, failed, skipped }

/// Welche Prüfung. Die Oberfläche übersetzt Art und Ergebnis in Text.
enum CheckKind {
  /// `GET /api/state` erreichbar?
  http,

  /// Antwort ist ein JSON-Objekt mit bekannten Feldern?
  stateFormat,

  /// Enthält der Zustand Würfe (`throws`)?
  throwsField,

  /// Läuft die Erkennung (`running`)?
  detection,

  /// WebSocket `/api/events` erreichbar und schickt Nachrichten?
  webSocket,
}

/// Mögliche Ursachen, damit die Oberfläche gezielte Hinweise geben kann.
enum CheckReason {
  none,
  refused,
  timeout,
  hostNotFound,
  unauthorized,
  httpStatus,
  notJson,
  missingThrows,
  boardEmpty,
  stopped,
  noMessages,
  quiet,
  other,
}

class DiagnosticCheck {
  const DiagnosticCheck(this.kind, this.result, {this.reason = CheckReason.none, this.detail = ''});
  final CheckKind kind;
  final CheckResult result;
  final CheckReason reason;

  /// Technische Einzelheiten (Statuscode, Fehlermeldung, Felder).
  final String detail;
}

/// Prüft Schritt für Schritt, ob der Board Manager erreichbar ist und
/// Würfe liefert. Ruft bewusst keine Endpunkte mit API-Key ab
/// (`/api/system`, `/api/config`).
class AutodartsDiagnostics {
  AutodartsDiagnostics({
    required this.host,
    this.port = 3180,
    http.Client? httpClient,
    WebSocketConnector? connector,
    this.timeout = const Duration(seconds: 4),
    this.messageWait = const Duration(seconds: 3),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _connector = connector ?? defaultWebSocketConnector;

  final String host;
  final int port;
  final Duration timeout;

  /// Wie lange nach dem Verbinden auf die erste WebSocket-Nachricht
  /// gewartet wird.
  final Duration messageWait;
  final http.Client _http;
  final bool _ownsHttp;
  final WebSocketConnector _connector;

  Uri get _stateUri => Uri(scheme: 'http', host: host, port: port, path: '/api/state');
  Uri get _wsUri => Uri(scheme: 'ws', host: host, port: port, path: '/api/events');

  Future<List<DiagnosticCheck>> run() async {
    try {
      final checks = <DiagnosticCheck>[];
      checks.addAll(await _checkHttp());
      checks.add(await _checkWebSocket());
      return checks;
    } finally {
      if (_ownsHttp) _http.close();
    }
  }

  Future<List<DiagnosticCheck>> _checkHttp() async {
    const skippedRest = [
      DiagnosticCheck(CheckKind.stateFormat, CheckResult.skipped),
      DiagnosticCheck(CheckKind.throwsField, CheckResult.skipped),
      DiagnosticCheck(CheckKind.detection, CheckResult.skipped),
    ];
    final watch = Stopwatch()..start();
    final http.Response res;
    try {
      res = await _http.get(_stateUri).timeout(timeout);
    } on TimeoutException {
      return [const DiagnosticCheck(CheckKind.http, CheckResult.failed, reason: CheckReason.timeout), ...skippedRest];
    } on SocketException catch (e) {
      final reason = _socketReason(e);
      return [DiagnosticCheck(CheckKind.http, CheckResult.failed, reason: reason, detail: e.message), ...skippedRest];
    } catch (e) {
      return [DiagnosticCheck(CheckKind.http, CheckResult.failed, reason: CheckReason.other, detail: '$e'), ...skippedRest];
    }
    final ms = watch.elapsedMilliseconds;
    if (res.statusCode == 401 || res.statusCode == 403) {
      return [
        DiagnosticCheck(CheckKind.http, CheckResult.failed, reason: CheckReason.unauthorized, detail: 'HTTP ${res.statusCode}'),
        ...skippedRest,
      ];
    }
    if (res.statusCode != 200) {
      return [
        DiagnosticCheck(CheckKind.http, CheckResult.failed, reason: CheckReason.httpStatus, detail: 'HTTP ${res.statusCode}'),
        ...skippedRest,
      ];
    }
    final checks = [DiagnosticCheck(CheckKind.http, CheckResult.ok, detail: 'HTTP 200 · $ms ms')];

    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      return [
        ...checks,
        const DiagnosticCheck(CheckKind.stateFormat, CheckResult.failed, reason: CheckReason.notJson),
        const DiagnosticCheck(CheckKind.throwsField, CheckResult.skipped),
        const DiagnosticCheck(CheckKind.detection, CheckResult.skipped),
      ];
    }
    if (decoded is! Map) {
      return [
        ...checks,
        DiagnosticCheck(CheckKind.stateFormat, CheckResult.failed, reason: CheckReason.notJson, detail: decoded.runtimeType.toString()),
        const DiagnosticCheck(CheckKind.throwsField, CheckResult.skipped),
        const DiagnosticCheck(CheckKind.detection, CheckResult.skipped),
      ];
    }
    const known = {'connected', 'running', 'status', 'event', 'numThrows', 'throws'};
    final keys = decoded.keys.map((k) => '$k').toList()..sort();
    final knownCount = keys.where(known.contains).length;
    checks.add(DiagnosticCheck(
      CheckKind.stateFormat,
      knownCount >= 2 ? CheckResult.ok : CheckResult.warning,
      reason: knownCount >= 2 ? CheckReason.none : CheckReason.other,
      detail: keys.join(', '),
    ));

    final throws = decoded['throws'];
    if (throws is List) {
      checks.add(DiagnosticCheck(CheckKind.throwsField, CheckResult.ok, detail: '${throws.length}'));
    } else if (decoded['numThrows'] == 0) {
      // Board Manager 2.0.2 lässt `throws` weg, solange kein Dart steckt.
      checks.add(const DiagnosticCheck(CheckKind.throwsField, CheckResult.skipped, reason: CheckReason.boardEmpty));
    } else {
      checks.add(const DiagnosticCheck(CheckKind.throwsField, CheckResult.warning, reason: CheckReason.missingThrows));
    }

    final running = decoded['running'];
    checks.add(switch (running) {
      true => DiagnosticCheck(CheckKind.detection, CheckResult.ok, detail: '${decoded['status'] ?? ''}'),
      false => DiagnosticCheck(CheckKind.detection, CheckResult.warning, reason: CheckReason.stopped, detail: '${decoded['status'] ?? ''}'),
      _ => const DiagnosticCheck(CheckKind.detection, CheckResult.skipped),
    });
    return checks;
  }

  Future<DiagnosticCheck> _checkWebSocket() async {
    try {
      final channel = await _connector(_wsUri).timeout(timeout);
      try {
        final first = await channel.stream.first.timeout(messageWait);
        final text = first is String ? first : utf8.decode(first as List<int>);
        String type = '?';
        try {
          final m = jsonDecode(text);
          if (m is Map && m['type'] is String) type = m['type'] as String;
        } on FormatException {
          // Kein JSON, Typ bleibt unbekannt.
        }
        return DiagnosticCheck(CheckKind.webSocket, CheckResult.ok, detail: type);
      } on TimeoutException {
        // Verbunden, aber still: Der Board Manager sendet nur bei Änderungen.
        return const DiagnosticCheck(CheckKind.webSocket, CheckResult.ok, reason: CheckReason.quiet);
      } on StateError {
        return const DiagnosticCheck(CheckKind.webSocket, CheckResult.warning, reason: CheckReason.noMessages);
      } finally {
        unawaited(channel.sink.close().catchError((_) {}));
      }
    } on TimeoutException {
      return const DiagnosticCheck(CheckKind.webSocket, CheckResult.failed, reason: CheckReason.timeout);
    } on SocketException catch (e) {
      return DiagnosticCheck(CheckKind.webSocket, CheckResult.failed, reason: _socketReason(e), detail: e.message);
    } catch (e) {
      final text = '$e';
      final unauthorized = text.contains('401') || text.contains('403');
      return DiagnosticCheck(
        CheckKind.webSocket,
        CheckResult.failed,
        reason: unauthorized ? CheckReason.unauthorized : CheckReason.other,
        detail: text,
      );
    }
  }

  static CheckReason _socketReason(SocketException e) {
    final msg = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    if (msg.contains('refused')) return CheckReason.refused;
    if (msg.contains('lookup') || msg.contains('host') && msg.contains('not')) return CheckReason.hostNotFound;
    if (msg.contains('timed out')) return CheckReason.timeout;
    return CheckReason.other;
  }
}
