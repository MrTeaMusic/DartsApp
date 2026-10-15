import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../sync/data/sync_server.dart' show syncKeyHeader;
import '../domain/screen_state.dart';
import 'screen_hub.dart';

/// Warum der zweite Bildschirm keine Verbindung bekommt.
enum ScreenFailure {
  /// PC nicht erreichbar (falsche Adresse, PC aus, Firewall, WLAN).
  unreachable,

  /// Hub antwortet, aber der Code passt nicht.
  wrongKey,

  /// Unter der Adresse läuft etwas anderes als DartLab.
  notDartLab,

  /// DartLab am PC ist zu alt (kennt den zweiten Bildschirm noch nicht).
  hubTooOld,
}

class ScreenConnectException implements Exception {
  const ScreenConnectException(this.kind, [this.detail]);
  final ScreenFailure kind;
  final String? detail;

  @override
  String toString() => 'ScreenConnectException($kind${detail == null ? '' : ': $detail'})';
}

/// Eine bestehende Verbindung zum Hub. [states] endet, wenn sie abreißt.
abstract class ScreenLink {
  Stream<ScreenState> get states;
  Future<void> close();
}

/// Baut eine Verbindung auf oder wirft [ScreenConnectException].
typedef ScreenConnector = Future<ScreenLink> Function({required String host, required int port, required String key});

/// Verbindet sich mit dem Hub: erst `GET /hello` (sagt, ob dort DartLab
/// läuft, ob der Code passt und ob der Hub den zweiten Bildschirm kennt),
/// dann der WebSocket.
Future<ScreenLink> connectScreen({
  required String host,
  required int port,
  required String key,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final http = HttpClient()..connectionTimeout = timeout;
  final Map<String, Object?> hello;
  try {
    final req = await http.get(host, port, '/hello').timeout(timeout);
    req.headers.set(syncKeyHeader, key);
    final res = await req.close().timeout(timeout);
    final text = await utf8.decodeStream(res).timeout(timeout);
    if (res.headers.value('X-DartLab') == null) throw const ScreenConnectException(ScreenFailure.notDartLab);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) throw const ScreenConnectException(ScreenFailure.notDartLab);
    hello = decoded;
  } on SocketException catch (e) {
    throw ScreenConnectException(ScreenFailure.unreachable, e.message);
  } on TimeoutException {
    throw const ScreenConnectException(ScreenFailure.unreachable, 'Zeitüberschreitung');
  } on HttpException catch (e) {
    throw ScreenConnectException(ScreenFailure.unreachable, e.message);
  } on FormatException {
    throw const ScreenConnectException(ScreenFailure.notDartLab);
  } finally {
    http.close(force: true);
  }
  if (hello['keyOk'] != true) throw const ScreenConnectException(ScreenFailure.wrongKey);
  if (hello['screen'] == null) throw const ScreenConnectException(ScreenFailure.hubTooOld);

  final WebSocket socket;
  try {
    socket = await WebSocket.connect('ws://$host:$port${ScreenPaths.socket}', headers: {syncKeyHeader: key}).timeout(timeout);
  } on SocketException catch (e) {
    throw ScreenConnectException(ScreenFailure.unreachable, e.message);
  } on WebSocketException catch (e) {
    throw ScreenConnectException(ScreenFailure.unreachable, e.message);
  } on TimeoutException {
    throw const ScreenConnectException(ScreenFailure.unreachable, 'Zeitüberschreitung');
  } on HttpException catch (e) {
    throw ScreenConnectException(ScreenFailure.unreachable, e.message);
  }
  // Merkt tote Verbindungen (PC aus, WLAN weg) nach wenigen Sekunden.
  socket.pingInterval = const Duration(seconds: 4);
  return _SocketLink(socket);
}

class _SocketLink implements ScreenLink {
  _SocketLink(this._socket);
  final WebSocket _socket;

  @override
  Stream<ScreenState> get states => _socket.transform(StreamTransformer<dynamic, ScreenState>.fromHandlers(
        handleData: (data, sink) {
          final state = decodeScreenMessage(data);
          if (state != null) sink.add(state);
        },
      ));

  @override
  Future<void> close() => _socket.close(WebSocketStatus.normalClosure);
}

/// Liest eine Nachricht des Hubs; `null` bei Unbekanntem.
ScreenState? decodeScreenMessage(Object? data) {
  if (data is! String) return null;
  try {
    final m = jsonDecode(data);
    if (m is! Map || m['type'] != 'state') return null;
    return ScreenState.fromJson(m['state']);
  } on FormatException {
    return null;
  }
}
