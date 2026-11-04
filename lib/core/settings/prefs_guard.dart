import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Schützt die Einstellungsdatei (`shared_preferences.json`) unter Windows
/// und Linux.
///
/// Das Paket schreibt die Datei bei jeder Änderung direkt und ohne
/// Zwischenschritt neu. Wird die App genau dabei hart beendet (Absturz,
/// Strom weg), ist die Datei leer oder halb geschrieben, und das Paket
/// stürzt beim nächsten Start beim Lesen ab oder startet ohne Einstellungen.
///
/// Der Schutz läuft vor dem ersten Zugriff aufs Paket:
/// * Ist die Datei gültig, wird sie als `.bak` gesichert (nur wenn sie sich
///   geändert hat).
/// * Ist sie leer oder kein gültiges JSON, kommt die Sicherung zurück. Die
///   kaputte Datei bleibt als `.defekt` liegen.
class PrefsGuard {
  PrefsGuard(this.file);

  final File file;

  File get _backup => File('${file.path}.bak');
  File get _broken => File('${file.path}.defekt');

  /// Standardpfad: derselbe wie im Paket (App-Support-Ordner).
  static Future<PrefsGuard?> forPlatform() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return null;
    final dir = await getApplicationSupportDirectory();
    return PrefsGuard(File(p.join(dir.path, 'shared_preferences.json')));
  }

  /// Prüft und sichert. Wirft nie: ein Fehler hier darf den Start nicht
  /// verhindern.
  Future<PrefsGuardResult> protect() async {
    try {
      if (!file.existsSync()) {
        // Datei fehlt ganz, die Sicherung rettet die Einstellungen.
        return _restoreOr(PrefsGuardResult.fresh);
      }
      final text = file.readAsStringSync();
      if (_isValid(text)) {
        if (!_backup.existsSync() || _backup.readAsStringSync() != text) {
          _backup.writeAsStringSync(text, flush: true);
        }
        return PrefsGuardResult.ok;
      }
      // Kaputt: zur Ansicht beiseitelegen, dann wiederherstellen.
      file.copySync(_broken.path);
      return _restoreOr(PrefsGuardResult.resetEmpty, brokenFile: true);
    } catch (e) {
      debugPrint('PrefsGuard: $e');
      return PrefsGuardResult.error;
    }
  }

  PrefsGuardResult _restoreOr(PrefsGuardResult fallback, {bool brokenFile = false}) {
    if (_backup.existsSync() && _isValid(_backup.readAsStringSync())) {
      _backup.copySync(file.path);
      return PrefsGuardResult.restored;
    }
    if (brokenFile) file.deleteSync(); // sonst stürzt das Paket beim Lesen ab
    return fallback;
  }

  static bool _isValid(String text) {
    if (text.trim().isEmpty) return false;
    try {
      return jsonDecode(text) is Map;
    } on FormatException {
      return false;
    }
  }
}

enum PrefsGuardResult {
  /// Datei gültig, Sicherung aktuell.
  ok,

  /// Erster Start, noch keine Datei und keine Sicherung.
  fresh,

  /// Datei war leer/defekt oder fehlte, Einstellungen aus der Sicherung zurück.
  restored,

  /// Datei war defekt und keine Sicherung da, startet mit Vorgaben.
  resetEmpty,

  error,
}
