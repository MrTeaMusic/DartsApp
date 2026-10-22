import 'dart:convert';

import 'package:dartlab/features/sync/data/cloud_api.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/data/cloud_remote.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sync_device.dart';

/// Der Cloud-Speicher im Speicher, mit den Regeln aus `cloud/worker.js`:
/// Tresor je Token, Meta mit Versionszähler (Compare-and-set), Session-Blöcke
/// mit (Stand, Darts)-Ordnung.
class FakeCloud {
  final vaults = <String, FakeVault>{};

  /// Zähler der Schreib- und Lesezugriffe.
  int metaPuts = 0;
  int sessionPuts = 0;
  int sessionGets = 0;
  final deleted = <String>[];

  /// Wird vor jedem Meta-PUT aufgerufen (um ein anderes Gerät dazwischenfunken
  /// zu lassen).
  Future<void> Function(String token)? beforeMetaPut;

  /// Ersetzt die Antwort, etwa um Fehler zu simulieren.
  http.Response? Function(http.Request)? override;

  /// Hält eine Anfrage an, bis das gelieferte `Future` fertig ist (um einen
  /// Ablauf mittendrin anzusehen).
  Future<void>? Function(http.Request)? hold;

  FakeVault vault(String token) => vaults.putIfAbsent(token, FakeVault.new);

  /// Alles, was auf dem Server liegt, als Text (zum Prüfen, dass kein Klartext dabei ist).
  String dump() => jsonEncode([
        for (final v in vaults.values) ...[v.meta, ...v.sessions.values.map((o) => o['body'])],
      ]);

  http.Client client() => MockClient((req) async {
        await hold?.call(req);
        final custom = override?.call(req);
        if (custom != null) return custom;
        return _handle(req);
      });

  http.Response _json(int status, Map<String, Object?> body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', 'x-dartlab-cloud': '1'});

  Future<http.Response> _handle(http.Request req) async {
    final path = req.url.path;
    if (path == '/v1/hello') return _json(200, {'app': 'dartlab-cloud', 'version': 1});
    final auth = req.headers['Authorization'] ?? '';
    if (!auth.startsWith('Bearer ') || auth.length != 7 + 64) return _json(401, {'error': 'unauthorized'});
    final token = auth.substring(7);
    final body = req.body.isEmpty ? <String, Object?>{} : jsonDecode(req.body) as Map<String, Object?>;
    if (path == '/v1/meta') {
      if (req.method == 'GET') {
        final m = vaults[token]?.meta;
        return m == null ? _json(404, {'error': 'no-vault'}) : _json(200, {'rev': vaults[token]!.rev, 'body': m});
      }
      await beforeMetaPut?.call(token);
      metaPuts++;
      final v = vault(token);
      if (body['ifRev'] != v.rev) return _json(409, {'error': 'conflict', 'rev': v.rev});
      v
        ..rev += 1
        ..meta = body['body'] as String;
      return _json(200, {'rev': v.rev});
    }
    if (path.startsWith('/v1/s/')) {
      final uid = path.substring('/v1/s/'.length);
      final v = vault(token);
      switch (req.method) {
        case 'GET':
          sessionGets++;
          final o = v.sessions[uid];
          return o == null ? _json(404, {'error': 'not-found'}) : _json(200, o);
        case 'PUT':
          sessionPuts++;
          final old = v.sessions[uid];
          final newer = old == null ||
              (body['stamp'] as int) > (old['stamp'] as int) ||
              (body['stamp'] == old['stamp'] && (body['darts'] as int) >= (old['darts'] as int));
          if (newer) v.sessions[uid] = body;
          return _json(200, {'stored': newer});
        case 'DELETE':
          deleted.add(uid);
          return _json(200, {'deleted': v.sessions.remove(uid) != null});
      }
    }
    return _json(404, {'error': 'not-found'});
  }
}

class FakeVault {
  int rev = 0;
  String? meta;
  final sessions = <String, Map<String, Object?>>{};
}

/// Abgleich eines [Device] mit dem Fake-Speicher.
class CloudDevice {
  CloudDevice(this.cloud, this.secret, {Device? device}) : device = device ?? Device();
  final FakeCloud cloud;
  final CloudSecret secret;
  final Device device;

  Future<SyncReport> sync({int attempts = 4}) async {
    final keys = await secret.keys();
    return SyncClient.remote(
      device.store,
      () => CloudRemote(CloudApi('https://sync.example.workers.dev', keys.token, client: cloud.client()), keys),
      chunk: 2,
      attempts: attempts,
    ).sync();
  }
}
