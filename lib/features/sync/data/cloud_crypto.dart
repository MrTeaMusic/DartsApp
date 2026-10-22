import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Das Geheimnis eines Cloud-Tresors: 128 zufällige Bit als 26 Zeichen
/// (Crockford-Base32, ohne die verwechselbaren Buchstaben I, L, O, U).
///
/// Aus ihm werden zwei Schlüssel abgeleitet: ein Zugangs-Token für den Server
/// und der Schlüssel, mit dem alle Daten verschlüsselt werden. Der Server
/// bekommt nur das Token, kann daraus aber nicht auf das Geheimnis oder den
/// Datenschlüssel schließen.
class CloudSecret {
  CloudSecret._(this.bytes);

  /// 16 Byte.
  final Uint8List bytes;

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int textLength = 26;

  static CloudSecret generate([Random? random]) {
    final r = random ?? Random.secure();
    return CloudSecret._(Uint8List.fromList(List.generate(16, (_) => r.nextInt(256))));
  }

  /// Das Geheimnis, wie es ein Mensch eintippt (Groß-/Kleinschreibung,
  /// Striche und Leerzeichen egal, O wie 0, I und L wie 1). `null`, wenn es
  /// nicht passt.
  static CloudSecret? tryParse(String input) {
    final t = normalize(input);
    if (t.length != textLength) return null;
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final c in t.split('')) {
      final v = _alphabet.indexOf(c);
      if (v < 0) return null;
      buffer = (buffer << 5) | v;
      bits += 5;
      while (bits >= 8 && out.length < 16) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    return out.length == 16 ? CloudSecret._(Uint8List.fromList(out)) : null;
  }

  /// Entfernt Trenner und vereinheitlicht verwechselbare Zeichen.
  static String normalize(String input) => input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-_.]'), '')
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');

  /// Roh, 26 Zeichen.
  String get text {
    final sb = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(_alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) sb.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return sb.toString();
  }

  /// In Vierergruppen zum Abschreiben: `ABCD-EFGH-…`.
  String get display {
    final t = text;
    return [for (var i = 0; i < t.length; i += 4) t.substring(i, i + 4 > t.length ? t.length : i + 4)].join('-');
  }

  Future<CloudKeys> keys() async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final root = SecretKey(bytes);
    final salt = utf8.encode('dartlab-cloud-v1');
    final token = await (await hkdf.deriveKey(secretKey: root, nonce: salt, info: utf8.encode('auth'))).extractBytes();
    final data = await hkdf.deriveKey(secretKey: root, nonce: salt, info: utf8.encode('data'));
    return CloudKeys._(_hex(token), data);
  }
}

String _hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// Zugangs-Token und Datenschlüssel eines Tresors.
class CloudKeys {
  CloudKeys._(this.token, this._data);

  /// 64 Hex-Zeichen, geht als `Authorization: Bearer` an den Server.
  final String token;
  final SecretKey _data;

  static final _aes = AesGcm.with256bits();

  /// Packt [json] (komprimiert) und verschlüsselt es; heraus kommt Base64
  /// aus Nonce, Chiffre und Prüfwert. [label] (z. B. `meta` oder `s:<uid>`)
  /// ist an die Verschlüsselung gebunden, der Server kann also keinen Eintrag
  /// unter einem anderen Namen unterschieben.
  Future<String> seal(Object json, String label) async {
    final plain = gzip.encode(utf8.encode(jsonEncode(json)));
    final box = await _aes.encrypt(plain, secretKey: _data, aad: utf8.encode(label));
    return base64.encode(box.concatenation());
  }

  /// Gegenstück zu [seal]. Wirft [CloudDecryptException], wenn der Schlüssel
  /// nicht passt oder die Daten verändert wurden.
  Future<Map<String, Object?>> open(String body, String label) async {
    try {
      final box = SecretBox.fromConcatenation(base64.decode(body), nonceLength: 12, macLength: 16);
      final plain = await _aes.decrypt(box, secretKey: _data, aad: utf8.encode(label));
      final decoded = jsonDecode(utf8.decode(gzip.decode(plain)));
      if (decoded is! Map<String, Object?>) throw const FormatException('Objekt erwartet');
      return decoded;
    } on SecretBoxAuthenticationError {
      throw const CloudDecryptException();
    } on FormatException {
      throw const CloudDecryptException();
    }
  }
}

class CloudDecryptException implements Exception {
  const CloudDecryptException();
  @override
  String toString() => 'CloudDecryptException';
}
