import 'dart:convert';
import 'dart:io';

import 'package:dartlab/features/update/data/update_client.dart';
import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:dartlab/features/update/presentation/update_controller.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String updateFixture(String name) => File('test/fixtures/update/$name').readAsStringSync();

/// Antwort von GitHub für [FakeGitHub].
typedef GitHubReply = http.Response Function();

/// Das Release aus der Fixture, auf Wunsch mit anderem Tag.
http.Response releaseReply({String? tag}) {
  var body = updateFixture('latest_release.json');
  if (tag != null) body = body.replaceAll('v0.10.0-b12', tag);
  return http.Response.bytes(utf8.encode(body), 200);
}

/// Das Release wie [releaseReply], dazu mit der APK der Lite-App.
http.Response releaseWithApkReply({String? tag}) {
  final t = tag ?? 'v0.10.0-b12';
  final json = jsonDecode(releaseReply(tag: tag).body) as Map<String, Object?>;
  (json['assets'] as List<Object?>).add({
    'name': 'DartLab-Lite-android.apk',
    'content_type': 'application/vnd.android.package-archive',
    'size': 31457280,
    'browser_download_url': 'https://github.com/MrTeaMusic/DartsApp/releases/download/$t/DartLab-Lite-android.apk',
  });
  return http.Response.bytes(utf8.encode(jsonEncode(json)), 200);
}

http.Response rateLimitReply() =>
    http.Response(updateFixture('rate_limited.json'), 403, headers: {'x-ratelimit-remaining': '0'});
http.Response offlineReply() => throw const SocketException('Failed host lookup');

/// Zählt Anfragen an die API; die Antwort ist austauschbar.
class FakeGitHub {
  FakeGitHub([this.reply = releaseReply]);
  GitHubReply reply;
  int calls = 0;

  late final http.Client client = MockClient((req) async {
    calls++;
    return reply();
  });
}

/// Download ohne Netz und ohne Dateisystem-Warten: schreibt sofort.
class FakeUpdateClient extends UpdateClient {
  FakeUpdateClient(FakeGitHub github) : super(github.client);
  bool fail = false;
  int downloads = 0;

  @override
  Future<File> download(ReleaseAsset asset, File target, {void Function(double? progress)? onProgress}) async {
    downloads++;
    onProgress?.call(0.5);
    if (fail) throw const UpdateException(UpdateFailure.offline);
    return target;
  }
}

class FakeUpdateHost extends UpdateHost {
  FakeUpdateHost({this.platform = ReleasePlatform.windows, this.isIos = false, String? downloads})
      : downloads = downloads ?? (Platform.isWindows ? r'C:\Users\ben\Downloads' : '/Users/ben/Downloads');

  @override
  final ReleasePlatform? platform;
  @override
  final bool isIos;
  final String downloads;
  final opened = <String>[];

  @override
  Future<Directory> downloadsDirectory() async => Directory(downloads);

  @override
  Future<bool> openFolder(Directory dir) async {
    opened.add(dir.path);
    return true;
  }

  @override
  Future<bool> openUrl(Uri url) async {
    opened.add('$url');
    return true;
  }
}

/// Überschreibungen für eine App mit Build-Nummer [build] (0 = selbst gebaut).
List<Override> updateOverrides({
  required FakeGitHub github,
  int build = 10,
  FakeUpdateHost? host,
  FakeUpdateClient? client,
  DateTime Function()? clock,
}) =>
    [
      currentBuildProvider.overrideWithValue(AppBuild('0.10.0', build)),
      updateHttpClientProvider.overrideWithValue(github.client),
      if (client != null) updateClientProvider.overrideWithValue(client),
      updateHostProvider.overrideWithValue(host ?? FakeUpdateHost()),
      if (clock != null) updateClockProvider.overrideWithValue(clock),
    ];
