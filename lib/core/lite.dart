import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ist das die „Lite“-Variante? Sie dient nur zum Ansehen der Statistik und
/// wird mit `--dart-define=DARTLAB_LITE=true` gebaut. Ohne die Angabe ist die
/// App die vollständige DartLab-App.
const bool kLiteBuild = bool.fromEnvironment('DARTLAB_LITE');

/// Läuft die App als Lite-Variante? In Tests überschreibbar.
final liteProvider = Provider<bool>((ref) => kLiteBuild);
