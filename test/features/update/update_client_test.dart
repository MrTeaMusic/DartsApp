import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartlab/features/update/data/update_client.dart';
import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String fixture(String name) => File('test/fixtures/update/$name').readAsStringSync();

Matcher failsWith(UpdateFailure f) =>
    throwsA(isA<UpdateException>().having((e) => e.failure, 'failure', f));

void main() {
  group('fetchLatest', () {
    test('fragt die öffentliche API ohne Token', () async {
      late http.Request seen;
      final client = UpdateClient(MockClient((req) async {
        seen = req;
        return http.Response.bytes(utf8.encode(fixture('latest_release.json')), 200);
      }));
      final r = await client.fetchLatest();
      expect(seen.url.toString(), 'https://api.github.com/repos/MrTeaMusic/DartsApp/releases/latest');
      expect(seen.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(r.build, const AppBuild('0.10.0', 12));
      expect(r.shortNotes().first, contains('Online-Matches'));
    });

    test('kein Release: 404', () {
      final client = UpdateClient(MockClient((_) async => http.Response(fixture('not_found.json'), 404)));
      expect(client.fetchLatest(), failsWith(UpdateFailure.noRelease));
    });

    test('Rate-Limit: 403 mit leerem Kontingent und 429', () {
      final limited = UpdateClient(MockClient(
        (_) async => http.Response(fixture('rate_limited.json'), 403, headers: {'x-ratelimit-remaining': '0'}),
      ));
      expect(limited.fetchLatest(), failsWith(UpdateFailure.rateLimited));
      final tooMany = UpdateClient(MockClient((_) async => http.Response('', 429)));
      expect(tooMany.fetchLatest(), failsWith(UpdateFailure.rateLimited));
      final forbidden = UpdateClient(MockClient((_) async => http.Response('', 403)));
      expect(forbidden.fetchLatest(), failsWith(UpdateFailure.other));
    });

    test('offline, Zeitüberschreitung, kaputte Antwort', () {
      final offline = UpdateClient(MockClient((_) async => throw const SocketException('Failed host lookup')));
      expect(offline.fetchLatest(), failsWith(UpdateFailure.offline));
      final client = UpdateClient(MockClient((_) async => throw http.ClientException('Connection closed')));
      expect(client.fetchLatest(), failsWith(UpdateFailure.offline));
      final slow = UpdateClient(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      expect(slow.fetchLatest(), failsWith(UpdateFailure.offline));
      final html = UpdateClient(MockClient((_) async => http.Response('<html>', 200)));
      expect(html.fetchLatest(), failsWith(UpdateFailure.other));
      final noTag = UpdateClient(MockClient((_) async => http.Response('{"tag_name":"nightly"}', 200)));
      expect(noTag.fetchLatest(), failsWith(UpdateFailure.noRelease));
      final server = UpdateClient(MockClient((_) async => http.Response('', 502)));
      expect(server.fetchLatest(), failsWith(UpdateFailure.other));
    });
  });

  group('download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dartlab-update-'));
    tearDown(() => dir.deleteSync(recursive: true));

    final asset = ReleaseAsset(
      name: 'DartLab-windows.zip',
      url: Uri.parse('https://github.com/MrTeaMusic/DartsApp/releases/download/v0.10.0-b12/DartLab-windows.zip'),
      size: 4000,
    );

    test('schreibt die Datei und meldet den Fortschritt', () async {
      final bytes = List.generate(4000, (i) => i % 256);
      final client = UpdateClient(MockClient.streaming((req, _) async {
        expect(req.url, asset.url);
        return http.StreamedResponse(
          Stream.fromIterable([for (var i = 0; i < 4; i++) bytes.sublist(i * 1000, (i + 1) * 1000)]),
          200,
          contentLength: 4000,
        );
      }));
      final progress = <double?>[];
      final target = File('${dir.path}/DartLab-windows-0.10.0-b12.zip');
      final file = await client.download(asset, target, onProgress: progress.add);
      expect(file.path, target.path);
      expect(file.readAsBytesSync(), bytes);
      expect(progress, [0.25, 0.5, 0.75, 1.0]);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('Abbruch hinterlässt keine halbe Datei', () async {
      final client = UpdateClient(MockClient.streaming((req, _) async {
        final c = StreamController<List<int>>();
        c.add([1, 2, 3]);
        c.addError(const SocketException('Verbindung weg'));
        unawaited(c.close());
        return http.StreamedResponse(c.stream, 200, contentLength: 4000);
      }));
      final target = File('${dir.path}/x.zip');
      await expectLater(client.download(asset, target), failsWith(UpdateFailure.offline));
      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('HTTP-Fehler', () async {
      final client = UpdateClient(MockClient.streaming((req, _) async => http.StreamedResponse(const Stream.empty(), 404)));
      await expectLater(client.download(asset, File('${dir.path}/x.zip')), failsWith(UpdateFailure.other));
    });
  });
}
