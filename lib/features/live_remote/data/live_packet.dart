import '../../second_screen/domain/screen_state.dart';
import '../../sync/data/cloud_crypto.dart';

/// Name des Live-Pakets. Er ist an die Verschlüsselung gebunden (wie `meta`
/// und `s:<uid>` beim Abgleich): Ein Paket unter anderem Namen lässt sich
/// nicht öffnen.
const String livePacketLabel = 'live';

/// Version des Paketformats. Neue Felder sind optional.
const int livePacketVersion = 1;

/// Das Live-Paket: der Spielstand, wie ihn auch der zweite Bildschirm
/// bekommt ([ScreenState], fertig beschriftet), und der Zeitpunkt des Sendens.
///
/// Im Klartext (vor dem Verschlüsseln und gzip):
/// `{"v": 1, "t": <Millisekunden seit 1970>, "state": { …ScreenState… }}`.
class LivePacket {
  const LivePacket({required this.state, required this.sentAt});

  final ScreenState state;

  /// Uhr des sendenden Geräts. Wie alt das Paket ist, sagt dem Zuschauer
  /// bevorzugt der Server (er hat nur eine Uhr); dies ist der Rückfall.
  final DateTime sentAt;

  Map<String, Object?> toJson() => {
        'v': livePacketVersion,
        't': sentAt.millisecondsSinceEpoch,
        'state': state.toJson(),
      };

  factory LivePacket.fromJson(Map<String, Object?> json) {
    final t = json['t'];
    return LivePacket(
      state: ScreenState.fromJson(json['state']),
      sentAt: DateTime.fromMillisecondsSinceEpoch(t is num ? t.toInt() : 0),
    );
  }
}

/// Verschlüsselt [packet] für den Cloud-Speicher (base64).
Future<String> sealLivePacket(CloudKeys keys, LivePacket packet) => keys.seal(packet.toJson(), livePacketLabel);

/// Öffnet ein Paket. Wirft [CloudDecryptException], wenn der Schlüssel nicht
/// passt (falsches Geheimnis) oder das Paket verändert wurde.
Future<LivePacket> openLivePacket(CloudKeys keys, String body) async => LivePacket.fromJson(await keys.open(body, livePacketLabel));
