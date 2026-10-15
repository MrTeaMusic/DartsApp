/// Angezeigte App-Version. Bei Änderungen auch `version` in pubspec.yaml
/// anpassen (ein Test prüft, dass beide gleich sind).
const appVersion = '0.10.0';

/// Version, die der Release-Workflow beim Bauen mitgibt
/// (`--dart-define=DARTLAB_VERSION=…`). Ohne Angabe gilt [appVersion].
const appVersionName = String.fromEnvironment('DARTLAB_VERSION', defaultValue: appVersion);

/// Build-Nummer aus dem Release-Workflow (`--dart-define=DARTLAB_BUILD=…`,
/// die Laufnummer auf GitHub). 0 heißt: selbst gebaut, z. B. mit
/// `flutter run`. Solche Builds melden nie von sich aus ein Update.
const appBuildNumber = int.fromEnvironment('DARTLAB_BUILD');
