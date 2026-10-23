import '../../../core/settings/app_settings.dart';
import '../../sync/domain/sync_role.dart';

/// Pfade der Lite-Variante. Dieselben Werte wie `Routes.stats` und
/// `Routes.settings` (ein Test prüft das), damit diese Datei den Router nicht
/// importieren muss.
abstract final class LiteRoutes {
  /// Einrichtung beim ersten Start, ohne Navigationsleiste.
  static const welcome = '/willkommen';
  static const stats = '/statistik';
  static const settings = '/einstellungen';

  /// Live-Reiter: Bens Spiel zuschauen.
  static const watch = '/zuschauen';
}

/// Ist die Verbindung zum Cloud-Speicher eingerichtet?
bool liteIsConnected(AppSettings s) =>
    s.syncRole == SyncRole.cloud && s.syncCloudUrl.trim().isNotEmpty && s.syncCloudSecret.isNotEmpty;

/// Weiterleitung der Lite-Variante: Ohne Einrichtung gibt es nur die
/// Einrichtung, mit Einrichtung nur Live, Statistik (mit Verlauf und Details)
/// und Optionen. Alle anderen Pfade, auch unbekannte, führen zur Statistik.
/// `null` heißt: Pfad bleibt.
String? liteRedirect(String path, {required bool connected}) {
  if (!connected) return path == LiteRoutes.welcome ? null : LiteRoutes.welcome;
  if (_allowed(path)) return null;
  return LiteRoutes.stats;
}

/// `/zuschauen`, `/statistik`, `/statistik/verlauf`, `/statistik/verlauf/<id>`
/// und `/einstellungen`, jeweils auch mit Schrägstrich am Ende.
final _allowedPaths = RegExp('^(${LiteRoutes.watch}|${LiteRoutes.stats}(/verlauf(/[^/]+)?)?|${LiteRoutes.settings})/?\$');

bool _allowed(String path) => _allowedPaths.hasMatch(path);
