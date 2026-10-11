import 'dart:math';

import 'package:flutter/foundation.dart';

/// Rolle dieses Geräts beim Abgleich im Heimnetz.
enum SyncRole {
  /// Kein Abgleich.
  off,

  /// Dieses Gerät (Windows oder Mac) nimmt Abgleiche an.
  hub,

  /// Dieses Gerät gleicht mit einem Hub ab.
  client,
}

/// Standard-Port des Hubs.
const int defaultSyncPort = 3190;

/// Neuer sechsstelliger Code für den Hub.
String newSyncKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

/// Nur Desktop-Apps können Hub sein (sie laufen am Board und dauerhaft).
bool get canBeHub => switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };
