import 'dart:convert';
import 'dart:isolate';

/// JSON großer Datenmengen (Abgleich, Sicherung) in einem Hintergrund-
/// Isolat umwandeln, damit die Oberfläche dabei nicht stehen bleibt. Kleine
/// Texte werden direkt umgewandelt, ein Isolat lohnt sich für sie nicht.
/// Das Ergebnis ist dasselbe wie mit `jsonDecode`/`jsonEncode`.
abstract final class BackgroundJson {
  /// Ab dieser Größe (Zeichen bzw. Bytes) im Hintergrund.
  static const int threshold = 64 * 1024;

  /// Wie `jsonDecode(text)`.
  static Future<Object?> decode(String text) async =>
      text.length < threshold ? jsonDecode(text) : Isolate.run(() => jsonDecode(text));

  /// Wie `jsonDecode(utf8.decode(bytes))`.
  static Future<Object?> decodeUtf8(List<int> bytes) async =>
      bytes.length < threshold ? jsonDecode(utf8.decode(bytes)) : Isolate.run(() => jsonDecode(utf8.decode(bytes)));

  /// Wie `utf8.encode(jsonEncode(value))`. Beim Übergeben ins Isolat wird
  /// [value] kopiert; das ist deutlich schneller als das Umwandeln selbst.
  static Future<List<int>> encodeUtf8(Object? value, {bool large = true}) async =>
      large ? Isolate.run(() => utf8.encode(jsonEncode(value))) : utf8.encode(jsonEncode(value));

  /// Ob ein Abgleich-Paket so viele Würfe hat, dass sich das Umwandeln im
  /// Hintergrund lohnt.
  static bool isLargeBundle(Object? body) => body is Map && body['throws'] is List && (body['throws'] as List).length > 1000;

  /// Wie `encoder.convert(value)`, im Hintergrund.
  static Future<String> encode(Object? value, {JsonEncoder encoder = const JsonEncoder()}) =>
      Isolate.run(() => encoder.convert(value));
}
