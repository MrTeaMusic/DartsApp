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

  /// Hub bzw. Cloud-Speicher meldet einen Fehler.
  server,

  /// Die Daten im Cloud-Speicher lassen sich mit dem Geheimnis nicht öffnen.
  wrongSecret,

  /// Unter der Adresse gibt es noch keinen Tresor (beim Verbinden mit einem
  /// vorhandenen).
  noVault,
}

/// Die Gegenseite eines Abgleichs: der Hub im Heimnetz ([HubRemote]) oder der
/// verschlüsselte Cloud-Speicher ([CloudRemote]).
abstract class SyncRemote {
  /// Tauscht die Manifeste. Der Hub übernimmt dabei Profile und Ziele des
  /// Geräts und meldet, was sich bei ihm geändert hat.
  Future<({SyncManifest manifest, MergeResult result})> exchange(SyncManifest mine);

  /// Schickt Sessions (samt Würfen) zur Gegenseite.
  Future<MergeResult> push(SyncBundle bundle);

  /// Holt die Sessions mit diesen IDs.
  Future<SyncBundle> pull(List<String> uids);

  /// Schließt den Abgleich ab, nachdem alles gesendet und geholt ist.
  /// `false`, wenn die Gegenseite sich inzwischen geändert hat; der Abgleich
  /// läuft dann noch einmal.
  Future<bool> commit(SyncStore store, SyncManifest theirs, SyncManifest mine) async => true;

  void close() {}
}

/// Gleicht mit einem [SyncRemote] ab. Läuft auf iPhone, iPad oder einem
/// zweiten Rechner.
class SyncClient {
  /// Abgleich mit einem Hub im Heimnetz.
  SyncClient(SyncStore store, {required String host, required int port, required String key, Duration timeout = const Duration(seconds: 8), int chunk = 25})
      : this.remote(store, () => HubRemote(host: host, port: port, key: key, timeout: timeout), chunk: chunk);

  /// Abgleich mit einer beliebigen Gegenseite; [open] liefert für jeden
  /// Durchlauf eine frische Verbindung.
  SyncClient.remote(this.store, this.open, {this.chunk = 25, this.attempts = 4});

  final SyncStore store;
  final SyncRemote Function() open;

  /// Wie oft ein Abgleich wiederholt wird, wenn sich die Gegenseite währenddessen
  /// geändert hat (mehrere Geräte gleichzeitig).
  final int attempts;

  /// Sessions pro Anfrage, damit große Bestände nicht in einer riesigen
  /// Nachricht landen. Klein genug, dass Lesen, Umwandeln und Übernehmen
  /// eines Pakets die Oberfläche (auch auf dem Hub) nicht spürbar anhalten.
  final int chunk;

  Future<SyncReport> sync() async {
    var sent = 0;
    var received = 0;
    var local = const MergeResult();
    var remote = const MergeResult();
    for (var attempt = 1;; attempt++) {
      final r = open();
      try {
        final report = await _once(r);
        sent += report.sent;
        received += report.received;
        local += report.local;
        remote += report.remote;
        if (report.committed || attempt >= attempts) {
          return SyncReport(sent: sent, received: received, local: local, remote: remote);
        }
      } finally {
        r.close();
      }
    }
  }

  Future<({int sent, int received, MergeResult local, MergeResult remote, bool committed})> _once(SyncRemote r) async {
    // 1. Manifeste tauschen; der Hub übernimmt dabei Profile und Ziele.
    final mine = await store.manifest();
    final reply = await r.exchange(mine);
    final theirs = reply.manifest;
    var remote = reply.result;
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
      remote += await r.push(await store.bundle(sessionUids: part));
    }

    // 3. Was hier fehlt oder älter ist, holen.
    final toFetch = {...theirs.sessionUids.difference(mine.sessionUids), ...theirs.newerThan(mine)}
        .where((u) => !deleted.contains(u))
        .toList()
      ..sort();
    for (var i = 0; i < toFetch.length; i += chunk) {
      final part = toFetch.sublist(i, (i + chunk).clamp(0, toFetch.length));
      local += await store.merge(await r.pull(part));
    }
    final committed = await r.commit(store, theirs, mine);
    return (sent: toSend.length, received: toFetch.length, local: local, remote: remote, committed: committed);
  }
}

/// Der Hub im Heimnetz (siehe [SyncServer]).
class HubRemote extends SyncRemote {
  HubRemote({required this.host, required this.port, required this.key, this.timeout = const Duration(seconds: 8)})
      : _http = HttpClient()..connectionTimeout = timeout;

  final String host;
  final int port;
  final String key;
  final Duration timeout;
  final HttpClient _http;

  @override
  void close() => _http.close(force: true);

  @override
  Future<({SyncManifest manifest, MergeResult result})> exchange(SyncManifest mine) async {
    final reply = await _post('/manifest', mine.toJson());
    return (
      manifest: SyncManifest.fromJson(reply['manifest'] as Map<String, Object?>),
      result: MergeResult.fromJson(reply['result'] as Map<String, Object?>),
    );
  }

  @override
  Future<MergeResult> push(SyncBundle bundle) async {
    final r = await _post('/push', bundle.toJson());
    return MergeResult.fromJson(r['result'] as Map<String, Object?>);
  }

  @override
  Future<SyncBundle> pull(List<String> uids) async => SyncBundle.fromJson(await _post('/pull', {'sessions': uids}));

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body) async {
    final HttpClientResponse res;
    try {
      final req = await _http.post(host, port, path).timeout(timeout);
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
