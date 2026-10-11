import 'dart:math';

final _random = Random.secure();

/// Geräteübergreifend eindeutige ID (128 Bit, hex) für Sync und Backup.
String newUid() => [for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

/// Feste ID des Standardprofils, damit das „Ich“ auf allen Geräten dasselbe
/// Profil ist.
const String defaultPlayerUid = 'default-player';
