import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/background_json.dart';
import 'sync_store.dart';

/// Kennung im Antwort-Header und im Gruß, damit der Client weiß, dass er
/// wirklich mit DartLab spricht.
const String syncProtocol = 'dartlab-sync';
const int syncProtocolVersion = 1;
const String syncKeyHeader = 'X-DartLab-Key';

/// Nimmt Abgleiche im Heimnetz an (läuft in der Desktop-App am Board).
///
/// Ablauf aus Sicht des Clients:
/// 1. `POST /manifest`: Client schickt sein Manifest, der Hub übernimmt
///    Profile und Ziele und antwortet mit seinem eigenen Manifest.
/// 2. `POST /push`: Sessions, die dem Hub fehlen.
/// 3. `POST /pull`: `{"sessions": [uid, …]}`, Antwort ist ein Paket.
///
/// Jede Anfrage braucht den Code aus den Einstellungen im Header
/// [syncKeyHeader].
class SyncServer {
  SyncServer(this.store, {required this.key, this.maxBodyBytes = 64 * 1024 * 1024});

  final SyncStore store;
  final String key;
  final int maxBodyBytes;

  HttpServer? _server;
  final _merged = StreamController<MergeResult>.broadcast();

  /// Meldet jede Übernahme, die etwas geändert hat (für Hinweise in der UI).
  Stream<MergeResult> get merged => _merged.stream;

  int? get port => _server?.port;
  bool get running => _server != null;

  Future<void> start({int port = 3190, Object? address}) async {
    if (_server != null) return;
    final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port, shared: true);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _merged.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('X-DartLab', '$syncProtocol/$syncProtocolVersion');
    try {
      if (req.method == 'GET' && req.uri.path == '/hello') {
        // Ohne Code: nur sagen, dass hier ein DartLab-Hub läuft.
        return await _json(res, {'app': syncProtocol, 'version': syncProtocolVersion, 'keyOk': _authorized(req)});
      }
      if (!_authorized(req)) return await _error(res, HttpStatus.unauthorized, 'Falscher Code');
      if (req.method != 'POST') return await _error(res, HttpStatus.methodNotAllowed, 'Nur POST');
      final body = await _readJson(req);
      if (body == null) return await _error(res, HttpStatus.requestEntityTooLarge, 'Zu groß');
      switch (req.uri.path) {
        case '/manifest':
          final r = await store.mergeMeta(SyncManifest.fromJson(body));
          _report(r);
          return await _json(res, {'manifest': (await store.manifest()).toJson(), 'result': r.toJson()});
        case '/push':
          final r = await store.merge(SyncBundle.fromJson(body));
          _report(r);
          return await _json(res, {'result': r.toJson()});
        case '/pull':
          final uids = [for (final u in (body['sessions'] as List? ?? const [])) '$u'];
          return await _json(res, (await store.bundle(sessionUids: uids)).toJson());
        default:
          return await _error(res, HttpStatus.notFound, 'Unbekannt');
      }
    } on FormatException catch (e) {
      return await _error(res, HttpStatus.badRequest, e.message);
    } on TypeError {
      return await _error(res, HttpStatus.badRequest, 'Ungültige Daten');
    } catch (e) {
      return await _error(res, HttpStatus.internalServerError, '$e');
    }
  }

  void _report(MergeResult r) {
    if (r.changedAnything && !_merged.isClosed) _merged.add(r);
  }

  bool _authorized(HttpRequest req) {
    final given = req.headers.value(syncKeyHeader);
    if (key.isEmpty || given == null || given.length != key.length) return false;
    var diff = 0;
    for (var i = 0; i < key.length; i++) {
      diff |= key.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<Map<String, Object?>?> _readJson(HttpRequest req) async {
    if (req.contentLength > maxBodyBytes) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    final decoded = await BackgroundJson.decodeUtf8(bytes.takeBytes());
    if (decoded is! Map<String, Object?>) throw const FormatException('Objekt erwartet');
    return decoded;
  }

  static Future<void> _json(HttpResponse res, Object body) async {
    res.headers.contentType = ContentType.json;
    res.add(await BackgroundJson.encodeUtf8(body, large: BackgroundJson.isLargeBundle(body)));
    await res.close();
  }

  static Future<void> _error(HttpResponse res, int status, String message) async {
    res.statusCode = status;
    await _json(res, {'error': message});
  }
}
