import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/app_release.dart';

/// Warum die Suche nach Updates nicht geklappt hat.
enum UpdateFailure {
  /// Kein Netz, Zeitüberschreitung, DNS.
  offline,

  /// GitHub erlaubt ohne Anmeldung 60 Anfragen pro Stunde und Adresse.
  rateLimited,

  /// Es gibt noch kein Release.
  noRelease,

  /// Unerwartete Antwort.
  other,
}

class UpdateException implements Exception {
  const UpdateException(this.failure, [this.detail]);
  final UpdateFailure failure;
  final String? detail;

  @override
  String toString() => 'UpdateException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// Fragt das neueste Release auf GitHub ab und lädt Dateien herunter.
/// Das Repository ist öffentlich, ein Token braucht es nicht.
class UpdateClient {
  UpdateClient(this._http, {this.timeout = const Duration(seconds: 10)});

  final http.Client _http;
  final Duration timeout;

  static const repo = 'MrTeaMusic/DartsApp';
  static final latestUrl = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
  static final releasesPage = Uri.parse('https://github.com/$repo/releases/latest');

  Future<AppRelease> fetchLatest() async {
    final http.Response res;
    try {
      res = await _http.get(latestUrl, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'DartLab-Update-Check',
      }).timeout(timeout);
    } on TimeoutException {
      throw const UpdateException(UpdateFailure.offline, 'timeout');
    } on SocketException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    } on HandshakeException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    }
    return parseLatest(res);
  }

  /// Wertet die Antwort aus (öffentlich für Tests).
  static AppRelease parseLatest(http.Response res) {
    if (res.statusCode == 404) throw const UpdateException(UpdateFailure.noRelease);
    if (res.statusCode == 429 || (res.statusCode == 403 && res.headers['x-ratelimit-remaining'] == '0')) {
      throw const UpdateException(UpdateFailure.rateLimited);
    }
    if (res.statusCode != 200) throw UpdateException(UpdateFailure.other, 'HTTP ${res.statusCode}');
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const UpdateException(UpdateFailure.other, 'kein JSON');
    }
    final release = AppRelease.fromJson(json);
    if (release == null) throw const UpdateException(UpdateFailure.noRelease, 'kein Versions-Tag');
    return release;
  }

  /// Lädt [asset] nach [target]. [onProgress] bekommt 0…1 (oder `null`,
  /// wenn die Größe unbekannt ist). Erst nach vollständigem Download wird
  /// die Datei umbenannt, ein Abbruch hinterlässt nur eine `.part`-Datei.
  Future<File> download(ReleaseAsset asset, File target, {void Function(double? progress)? onProgress}) async {
    final part = File('${target.path}.part');
    IOSink? sink;
    try {
      final res = await _http.send(http.Request('GET', asset.url)).timeout(timeout);
      if (res.statusCode != 200) throw UpdateException(UpdateFailure.other, 'HTTP ${res.statusCode}');
      final total = res.contentLength ?? (asset.size > 0 ? asset.size : null);
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null || total == 0 ? null : (received / total).clamp(0, 1).toDouble());
      }
      await sink.close();
      sink = null;
      if (target.existsSync()) target.deleteSync();
      return part.renameSync(target.path);
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException(UpdateFailure.offline, 'timeout');
    } on SocketException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    } on FileSystemException catch (e) {
      throw UpdateException(UpdateFailure.other, e.message);
    } finally {
      await sink?.close();
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } on FileSystemException {
          // Egal: bleibt als .part liegen.
        }
      }
    }
  }
}
