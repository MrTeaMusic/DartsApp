import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/background_json.dart';
import '../domain/imported_match.dart';
import 'autodarts_import_service.dart';

/// Header-Name für den Code (derselbe Name wie beim Sync-Hub).
const String importKeyHeader = 'X-DartLab-Key';

/// Standard-Port des Empfängers (der Sync-Hub nutzt 3190).
const int defaultImportPort = 3191;

/// Pfade des Empfängers.
abstract final class ImportPaths {
  static const String autodarts = '/import/autodarts';
  static const String ping = '/import/ping';
}

/// Nur diese Seiten dürfen den Empfänger aus dem Browser ansprechen.
const Set<String> importAllowedOrigins = {'https://play.autodarts.com', 'https://play.autodarts.io'};

/// Verarbeitet ein empfangenes Match. [id] ist die Match-Id aus der Adresse
/// der Anfrage (`?id=`), falls das Skript sie mitschickt.
typedef ImportHandler = Future<ImportReply> Function(Object? json, {String? id});

/// Kleiner HTTP-Server, der nur auf 127.0.0.1 lauscht und Matches aus dem
/// Browser-Skript annimmt (`POST /import/autodarts`).
///
/// Absicherung:
/// * Bindet ausschließlich an die Loopback-Adresse; erreichbar nur von diesem
///   Rechner, nicht im Netzwerk.
/// * Der `Host`-Header muss `127.0.0.1` oder `localhost` sein (Schutz vor
///   DNS-Rebinding).
/// * Jede Anfrage braucht den Code im Header [importKeyHeader].
/// * CORS nur für [importAllowedOrigins]. Ein anderer `Origin` bekommt 403
///   ohne Freigabe-Header; Anfragen ohne `Origin` (curl, Tests) sind erlaubt.
/// * Nur `POST`, nur JSON, Körper höchstens [maxBodyBytes], höchstens
///   [maxRequests] Anfragen je [window].
/// * Nichts wird protokolliert.
class AutodartsReceiver {
  AutodartsReceiver({
    required this.key,
    required this.handler,
    this.maxBodyBytes = 2 * 1024 * 1024,
    this.maxRequests = 30,
    this.window = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String key;
  final ImportHandler handler;
  final int maxBodyBytes;
  final int maxRequests;
  final Duration window;
  final DateTime Function() _clock;

  HttpServer? _server;
  final List<DateTime> _recent = [];

  int? get port => _server?.port;
  bool get running => _server != null;

  /// Lauscht auf 127.0.0.1:[port] (0 = freier Port). Wirft [SocketException],
  /// wenn der Port belegt ist.
  Future<void> start({int port = defaultImportPort}) async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  // ----------------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    try {
      if (!_hostOk(req)) return await _error(res, HttpStatus.forbidden, 'Falscher Host');

      final origin = req.headers.value('origin');
      final allowed = origin != null && importAllowedOrigins.contains(origin);
      if (origin != null && !allowed) return await _error(res, HttpStatus.forbidden, 'Origin nicht erlaubt');
      if (allowed) {
        res.headers
          ..set('Access-Control-Allow-Origin', origin)
          ..set('Vary', 'Origin');
      }

      if (_limited()) {
        res.headers.set('Retry-After', '${window.inSeconds}');
        return await _error(res, HttpStatus.tooManyRequests, 'Zu viele Anfragen');
      }

      final path = req.uri.path;
      if (path != ImportPaths.autodarts && path != ImportPaths.ping) {
        return await _error(res, HttpStatus.notFound, 'Unbekannt');
      }
      if (req.method == 'OPTIONS') {
        if (allowed) {
          res.headers
            ..set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
            ..set('Access-Control-Allow-Headers', 'Content-Type, $importKeyHeader')
            ..set('Access-Control-Max-Age', '600');
          // Chrome fragt bei Zugriffen auf den eigenen Rechner zusätzlich danach.
          if (req.headers.value('access-control-request-private-network') == 'true') {
            res.headers.set('Access-Control-Allow-Private-Network', 'true');
          }
        }
        res.statusCode = HttpStatus.noContent;
        return await res.close();
      }

      final wanted = path == ImportPaths.ping ? 'GET' : 'POST';
      if (req.method != wanted) {
        res.headers.set('Allow', '$wanted, OPTIONS');
        return await _error(res, HttpStatus.methodNotAllowed, 'Nur $wanted');
      }
      if (!_keyOk(req.headers.value(importKeyHeader))) return await _error(res, HttpStatus.unauthorized, 'Falscher Code');
      if (path == ImportPaths.ping) return await _json(res, HttpStatus.ok, {'ok': true, 'app': 'dartlab-import', 'version': 1});

      final type = req.headers.contentType?.mimeType;
      if (type != 'application/json' && type != 'text/plain') {
        return await _error(res, HttpStatus.unsupportedMediaType, 'Nur JSON');
      }
      final body = await _readBody(req);
      if (body == null) {
        res.headers.persistentConnection = false;
        return await _error(res, HttpStatus.requestEntityTooLarge, 'Zu groß');
      }
      final Object? json;
      try {
        json = await BackgroundJson.decodeUtf8(body);
      } on FormatException {
        return await _error(res, HttpStatus.badRequest, 'Kein gültiges JSON');
      }
      final id = _cleanId(req.uri.queryParameters['id']);
      final reply = await handler(json, id: id);
      return await _json(res, HttpStatus.ok, {
        'ok': true,
        'status': reply.status.name,
        'id': reply.id ?? id,
        'opponent': ?reply.opponent,
        if (reply.plan != null) 'legs': '${reply.plan!.legsMe}:${reply.plan!.legsOpponent}',
        'message': ?reply.message,
        if (reply.overlapStartedAt != null) 'overlap': true,
      });
    } on AutodartsImportException catch (e) {
      return await _error(res, HttpStatus.unprocessableEntity, e.message);
    } catch (_) {
      // Keine Einzelheiten nach außen, nichts ins Protokoll.
      return await _error(res, HttpStatus.internalServerError, 'Interner Fehler');
    }
  }

  bool _hostOk(HttpRequest req) {
    final host = req.headers.value('host') ?? '';
    final name = host.startsWith('[') ? host : host.split(':').first;
    return name == '127.0.0.1' || name == 'localhost';
  }

  /// Zählt die Anfrage; `true`, wenn das Limit überschritten ist.
  bool _limited() {
    final now = _clock();
    _recent.removeWhere((t) => now.difference(t) >= window);
    if (_recent.length >= maxRequests) return true;
    _recent.add(now);
    return false;
  }

  bool _keyOk(String? given) {
    if (key.isEmpty || given == null || given.length != key.length) return false;
    var diff = 0;
    for (var i = 0; i < key.length; i++) {
      diff |= key.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return diff == 0;
  }

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.-]{1,80}$');
  static String? _cleanId(String? id) => id != null && _idPattern.hasMatch(id) ? id : null;

  /// Liest den Körper bis [maxBodyBytes]; `null`, wenn er größer ist.
  Future<Uint8List?> _readBody(HttpRequest req) async {
    if (req.contentLength > maxBodyBytes) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return bytes.takeBytes();
  }

  static Future<void> _json(HttpResponse res, int status, Object body) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.add(utf8.encode(jsonEncode(body)));
    await res.close();
  }

  static Future<void> _error(HttpResponse res, int status, String message) =>
      _json(res, status, {'ok': false, 'error': message});
}
