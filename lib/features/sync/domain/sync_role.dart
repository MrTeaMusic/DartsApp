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
