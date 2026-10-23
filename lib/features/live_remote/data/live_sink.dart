import 'package:http/http.dart' as http;

import '../../second_screen/domain/screen_state.dart';
import '../../sync/data/cloud_api.dart';
import '../../sync/data/cloud_crypto.dart';
import 'live_packet.dart';

/// Wohin der [LivePusher] seine Stände schickt.
abstract class LiveSink {
  /// Prüft, ob der Cloud-Speicher Live kennt. Wirft [CloudTooOldException]
  /// bei einem alten Worker.
  Future<void> check();

  /// Verschlüsselt [state] und schickt ihn.
  Future<void> send(ScreenState state);

  void close();
}

/// Schickt über [CloudApi] (`PUT /v1/live`).
class CloudLiveSink implements LiveSink {
  CloudLiveSink(this.api, this.keys, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final CloudApi api;
  final CloudKeys keys;
  final DateTime Function() _now;

  /// Baut Schlüssel und Verbindung aus Adresse und Geheimnis. `null`, wenn
  /// eins davon nicht taugt.
  static Future<CloudLiveSink?> create(String url, String secret, {http.Client? client, Duration timeout = const Duration(seconds: 8)}) async {
    final parsed = CloudSecret.tryParse(secret);
    if (parsed == null || CloudApi.tryParseUrl(url) == null) return null;
    final keys = await parsed.keys();
    return CloudLiveSink(CloudApi(url, keys.token, client: client, timeout: timeout), keys);
  }

  @override
  Future<void> check() async {
    final hello = await api.hello();
    if (!hello.hasLive) throw const CloudTooOldException();
  }

  @override
  Future<void> send(ScreenState state) async {
    await api.putLive(await sealLivePacket(keys, LivePacket(state: state, sentAt: _now())));
  }

  @override
  void close() => api.close();
}
