import 'dart:io';

import 'package:flutter/foundation.dart';

import 'shared_match.dart';

/// Meldet `.dartlab` beim Start unter Windows für den angemeldeten Benutzer
/// an (HKCU, ohne Administratorrechte), damit ein Doppelklick auf eine
/// geteilte Datei DartLab öffnet. Ohne Installer und ohne Handgriff: Wer die
/// entpackte App an einen anderen Ort legt, bekommt beim nächsten Start den
/// neuen Pfad eingetragen.
const windowsProgId = 'DartLab.Match';

/// `reg add`-Aufrufe für [exe]. Als eigene Funktion, damit ein Test sie
/// prüfen kann.
List<List<String>> windowsFileTypeCommands(String exe) {
  const root = r'HKCU\Software\Classes';
  List<String> add(String key, {String? name, required String value}) =>
      ['add', '$root\\$key', if (name == null) '/ve' else ...['/v', name], '/d', value, '/f'];
  return [
    add('.$sharedMatchExtension', value: windowsProgId),
    add(windowsProgId, value: 'DartLab-Match'),
    add('$windowsProgId\\DefaultIcon', value: '"$exe",0'),
    add('$windowsProgId\\shell\\open\\command', value: '"$exe" "%1"'),
  ];
}

/// Trägt die Dateizuordnung ein, wenn sie fehlt oder auf einen anderen Pfad
/// zeigt. Fehler werden verschluckt: Die App läuft auch ohne.
Future<void> registerWindowsFileType() async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    final exe = Platform.resolvedExecutable;
    final current = await Process.run('reg', ['query', r'HKCU\Software\Classes\' '$windowsProgId\\shell\\open\\command', '/ve']);
    if (current.exitCode == 0 && '${current.stdout}'.toLowerCase().contains(exe.toLowerCase())) return;
    for (final args in windowsFileTypeCommands(exe)) {
      await Process.run('reg', args);
    }
    // Explorer neu über die Zuordnung informieren, damit das Symbol sofort stimmt.
    await Process.run('ie4uinit.exe', ['-show']);
  } on Exception {
    // Keine Rechte oder kein reg.exe: ohne Zuordnung weiterlaufen.
  }
}
