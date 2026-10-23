import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'sync_client.dart';

/// Antwort auf `GET /v1/meta`.
class CloudMeta {
  const CloudMeta(this.rev, this.body);
  final int rev;
  final String body;
}

/// Antwort auf `GET /v1/s/<uid>`.
class CloudObject {
  const CloudObject({required this.stamp, required this.darts, required this.body});
  final int stamp;
  final int darts;
  final String body;
}

/// Antwort auf `GET /v1/hello`: was der Worker kann.
class CloudHello {
  const CloudHello({this.live = 0});

  /// Version der Live-Fähigkeit (`/v1/live`); 0 bei einem alten Worker.
  final int live;

  bool get hasLive => live >= 1;
}

/// Antwort auf `GET /v1/live`. Ohne [body] hat sich seit der angefragten
/// Version nichts geändert (HTTP 304).
class CloudLiveReply {
  const CloudLiveReply({required this.rev, this.body, this.age});

  /// Zähler des Pakets (steigt mit jedem Senden).
  final int rev;

  /// Das verschlüsselte Paket; `null` bei 304.
  final String? body;

  /// Alter des Pakets nach der Uhr des Servers.
  final Duration? age;

  bool get notModified => body == null;
}

/// Der Cloud-Speicher kennt `/v1/live` nicht: Der Worker ist noch die alte
/// Fassung und muss neu eingefügt werden (siehe `cloud/README.md`).
class CloudTooOldException implements Exception {
  const CloudTooOldException();
  @override
  String toString() => 'CloudTooOldException';
}

/// Spricht mit dem Cloud-Speicher (siehe `cloud/README.md`). Der Server kennt
/// nur verschlüsselte Blöcke; alles Weitere passiert in [CloudRemote].
class CloudApi {
  CloudApi(String baseUrl, this.token, {http.Client? client, this.timeout = const Duration(seconds: 25)})
      : base = _normalize(baseUrl),
        _client = client ?? http.Client();

  final Uri base;
  final String token;
  final Duration timeout;
  final http.Client _client;

  /// `meine-app.workers.dev` oder `https://…/` werden zu einer Adresse mit
  /// `https://` und ohne Schrägstrich am Ende. `null`, wenn sie nicht taugt.
  static Uri? tryParseUrl(String input) {
    final t = input.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(t.contains('://') ? t : 'https://$t');
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && _isLocal(uri.host))) return null;
    return uri;
  }

  static bool _isLocal(String host) => host == 'localhost' || host == '127.0.0.1';

  static Uri _normalize(String input) {
    final uri = tryParseUrl(input);
    if (uri == null) throw const SyncException(SyncFailure.notDartLab, 'Adresse');
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    return uri.replace(path: path, query: '', fragment: '');
  }

  void close() => _client.close();

  /// Prüft, ob unter der Adresse ein DartLab-Cloud-Speicher antwortet, und
  /// sagt, was er kann.
  Future<CloudHello> hello() async {
    final r = await _send('GET', '/v1/hello', auth: false);
    final j = r.json;
    if (r.status != 200 || j is! Map || j['app'] != 'dartlab-cloud') throw const SyncException(SyncFailure.notDartLab);
    final live = j['live'];
    return CloudHello(live: live is num ? live.toInt() : 0);
  }

  /// Holt das Live-Paket. [since]: die zuletzt bekannte Version, bei
  /// unverändertem Stand antwortet der Server mit 304 (kein Inhalt).
  /// `null`, wenn der Tresor noch kein Live-Paket hat. Wirft
  /// [CloudTooOldException] bei einem alten Worker und
  /// `SyncException(noVault)`, wenn es zum Geheimnis keinen Tresor gibt.
  Future<CloudLiveReply?> getLive({int? since}) async {
    final r = await _send('GET', '/v1/live', query: since == null ? null : 'since=$since');
    final age = int.tryParse(r.headers['x-live-age'] ?? '');
    final duration = age == null ? null : Duration(milliseconds: age);
    final etag = int.tryParse((r.headers['etag'] ?? '').replaceAll('"', ''));
    if (r.status == 304 && (since != null || etag != null)) return CloudLiveReply(rev: since ?? etag!, age: duration);
    if (r.status == 404) {
      final error = r.json is Map ? (r.json as Map)['error'] : null;
      if (error == 'no-live') return null;
      if (error == 'no-vault') throw const SyncException(SyncFailure.noVault);
      throw const CloudTooOldException();
    }
    final j = _ok(r);
    return CloudLiveReply(rev: (j['rev'] as num).toInt(), body: j['body'] as String, age: duration);
  }

  /// Ersetzt das Live-Paket (der letzte gewinnt). Wirft
  /// [CloudTooOldException] bei einem alten Worker.
  Future<void> putLive(String body) async {
    final r = await _send('PUT', '/v1/live', body: {'body': body});
    if (r.status == 404) throw const CloudTooOldException();
    _ok(r);
  }

  /// `null`, wenn es den Tresor noch nicht gibt.
  Future<CloudMeta?> getMeta() async {
    final r = await _send('GET', '/v1/meta');
    if (r.status == 404) return null;
    final j = _ok(r);
    return CloudMeta((j['rev'] as num).toInt(), j['body'] as String);
  }

  /// Schreibt die Meta, wenn sie noch bei [ifRev] steht. Gibt die neue
  /// Version zurück oder `null` bei einem Konflikt (ein anderes Gerät war
  /// schneller).
  Future<int?> putMeta(int ifRev, String body) async {
    final r = await _send('PUT', '/v1/meta', body: {'ifRev': ifRev, 'body': body});
    if (r.status == 409) return null;
    return (_ok(r)['rev'] as num).toInt();
  }

  Future<CloudObject?> getSession(String uid) async {
    final r = await _send('GET', '/v1/s/$uid');
    if (r.status == 404) return null;
    final j = _ok(r);
    return CloudObject(stamp: (j['stamp'] as num).toInt(), darts: (j['darts'] as num).toInt(), body: j['body'] as String);
  }

  /// `true`, wenn der Server den Block übernommen hat (er behält einen
  /// neueren Stand).
  Future<bool> putSession(String uid, CloudObject object) async {
    final r = await _send('PUT', '/v1/s/$uid', body: {'stamp': object.stamp, 'darts': object.darts, 'body': object.body});
    return _ok(r)['stored'] == true;
  }

  Future<void> deleteSession(String uid) async {
    _ok(await _send('DELETE', '/v1/s/$uid'));
  }

  Map<String, Object?> _ok(_Reply r) {
    final j = r.json;
    if (r.status == 401) throw const SyncException(SyncFailure.wrongKey);
    if (r.status != 200 || j is! Map<String, Object?>) {
      throw SyncException(SyncFailure.server, j is Map && j['error'] != null ? '${j['error']}' : 'HTTP ${r.status}');
    }
    return j;
  }

  Future<_Reply> _send(String method, String path, {Map<String, Object?>? body, bool auth = true, String? query}) async {
    // Ohne Anhängsel „?“, wenn es keine Abfrage gibt.
    final uri = Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null, path: base.path + path, query: query);
    final req = http.Request(method, uri);
    if (auth) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout)).timeout(timeout);
    } on IOException catch (e) {
      throw SyncException(SyncFailure.unreachable, '$e');
    } on http.ClientException catch (e) {
      throw SyncException(SyncFailure.unreachable, e.message);
    } on TimeoutException {
      throw const SyncException(SyncFailure.unreachable, 'Zeitüberschreitung');
    }
    if (res.headers['x-dartlab-cloud'] == null) {
      // Cloudflare antwortet beim Überschreiten der Tageslimits selbst.
      if (res.statusCode == 429 || res.statusCode == 503) throw SyncException(SyncFailure.server, 'HTTP ${res.statusCode}');
      throw const SyncException(SyncFailure.notDartLab);
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      json = null;
    }
    return _Reply(res.statusCode, json, res.headers);
  }
}

class _Reply {
  const _Reply(this.status, this.json, this.headers);
  final int status;
  final Object? json;

  /// Kopfzeilen, Namen kleingeschrieben.
  final Map<String, String> headers;
}
