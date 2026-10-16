import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/background_json.dart';
import 'sync_server.dart';
import 'sync_store.dart';

/// Ergebnis eines Abgleichs aus Sicht dieses Geräts.
class SyncReport {
  const SyncReport({required this.sent, required this.received, required this.local, required this.remote});

  /// Sessions, die zum Hub geschickt bzw. vom Hub geholt wurden.
  final int sent;
  final int received;

  /// Was sich hier bzw. auf dem Hub geändert hat.
  final MergeResult local;
  final MergeResult remote;
}

/// Was beim Abgleich schiefgehen kann, mit einer Meldung für die UI.
class SyncException implements Exception {
  const SyncException(this.kind, [this.detail]);
  final SyncFailure kind;
  final String? detail;
  @override
  String toString() => 'SyncException($kind${detail == null ? '' : ': $detail'})';
}

enum SyncFailure {
  /// Hub nicht erreichbar (falsche IP, PC aus, Firewall).
  unreachable,

  /// Hub antwortet, aber der Code passt nicht.
  wrongKey,

  /// Unter der Adresse läuft etwas anderes als DartLab.
  notDartLab,

  /// Hub meldet einen Fehler.
  server,
}

/// Gleicht mit einem [SyncServer] ab. Läuft auf iPhone, iPad oder einem
/// zweiten Rechner.
class SyncClient {
  SyncClient(this.store, {required this.host, required this.port, required this.key, this.timeout = const Duration(seconds: 8), this.chunk = 25});

  final SyncStore store;
  final String host;
  final int port;
  final String key;
  final Duration timeout;

  /// Sessions pro Anfrage, damit große Bestände nicht in einer riesigen
  /// Nachricht landen. Klein genug, dass Lesen, Umwandeln und Übernehmen
  /// eines Pakets die Oberfläche (auch auf dem Hub) nicht spürbar anhalten.
  final int chunk;

  Future<SyncReport> sync() async {
    final http = HttpClient()..connectionTimeout = timeout;
    try {
      // 1. Manifeste tauschen; der Hub übernimmt dabei Profile und Ziele.
      final mine = await store.manifest();
      final reply = await _post(http, '/manifest', mine.toJson());
      final theirs = SyncManifest.fromJson(reply['manifest'] as Map<String, Object?>);
      var remote = MergeResult.fromJson(reply['result'] as Map<String, Object?>);
      var local = await store.mergeMeta(theirs);

      // 2. Was dem Hub fehlt oder auf dem Hub älter ist, hinschicken. Sessions,
      // die einer von beiden gelöscht hat, bleiben außen vor (Löschen gewinnt).
      final deleted = {
        for (final m in [mine, theirs]) for (final d in m.deletedSessions) d['uid'],
      };
      final toSend = {...mine.sessionUids.difference(theirs.sessionUids), ...mine.newerThan(theirs)}
          .where((u) => !deleted.contains(u))
          .toList()
        ..sort();
      for (var i = 0; i < toSend.length; i += chunk) {
        final part = toSend.sublist(i, (i + chunk).clamp(0, toSend.length));
        final r = await _post(http, '/push', (await store.bundle(sessionUids: part)).toJson());
        remote += MergeResult.fromJson(r['result'] as Map<String, Object?>);
      }

      // 3. Was hier fehlt oder älter ist, holen.
      final toFetch = {...theirs.sessionUids.difference(mine.sessionUids), ...theirs.newerThan(mine)}
          .where((u) => !deleted.contains(u))
          .toList()
        ..sort();
      for (var i = 0; i < toFetch.length; i += chunk) {
        final part = toFetch.sublist(i, (i + chunk).clamp(0, toFetch.length));
        final r = await _post(http, '/pull', {'sessions': part});
        local += await store.merge(SyncBundle.fromJson(r));
      }
      return SyncReport(sent: toSend.length, received: toFetch.length, local: local, remote: remote);
    } finally {
      http.close(force: true);
    }
  }

  Future<Map<String, Object?>> _post(HttpClient http, String path, Map<String, Object?> body) async {
    final HttpClientResponse res;
    try {
      final req = await http.post(host, port, path).timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.headers.set(syncKeyHeader, key);
      req.add(await BackgroundJson.encodeUtf8(body, large: BackgroundJson.isLargeBundle(body)));
      res = await req.close().timeout(timeout * 4);
    } on SocketException catch (e) {
      throw SyncException(SyncFailure.unreachable, e.message);
    } on TimeoutException {
      throw const SyncException(SyncFailure.unreachable, 'Zeitüberschreitung');
    } on HttpException catch (e) {
      throw SyncException(SyncFailure.unreachable, e.message);
    }
    final text = await utf8.decodeStream(res);
    if (res.headers.value('X-DartLab') == null) throw const SyncException(SyncFailure.notDartLab);
    if (res.statusCode == HttpStatus.unauthorized) throw const SyncException(SyncFailure.wrongKey);
    Object? decoded;
    try {
      decoded = await BackgroundJson.decode(text);
    } on FormatException {
      throw const SyncException(SyncFailure.notDartLab);
    }
    if (res.statusCode != HttpStatus.ok || decoded is! Map<String, Object?>) {
      throw SyncException(SyncFailure.server, decoded is Map ? '${decoded['error']}' : 'HTTP ${res.statusCode}');
    }
    return decoded;
  }
}
