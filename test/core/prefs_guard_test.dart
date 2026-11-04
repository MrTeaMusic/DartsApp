import 'dart:io';

import 'package:dartlab/core/settings/prefs_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;
  late PrefsGuard guard;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('prefs_guard');
    file = File('${dir.path}/shared_preferences.json');
    guard = PrefsGuard(file);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const good = '{"settings.look":"arena","sync.key":"abc"}';

  test('erster Start: nichts zu tun', () async {
    expect(await guard.protect(), PrefsGuardResult.fresh);
    expect(file.existsSync(), isFalse);
  });

  test('gültige Datei wird gesichert', () async {
    file.writeAsStringSync(good);
    expect(await guard.protect(), PrefsGuardResult.ok);
    expect(File('${file.path}.bak').readAsStringSync(), good);
  });

  test('Sicherung folgt der neuesten gültigen Datei', () async {
    file.writeAsStringSync(good);
    await guard.protect();
    file.writeAsStringSync('{"settings.look":"tv"}');
    await guard.protect();
    expect(File('${file.path}.bak').readAsStringSync(), '{"settings.look":"tv"}');
  });

  for (final broken in ['', '   ', '{"settings.look":"ar', '[1,2]', 'kein json']) {
    test('defekte Datei "$broken" wird aus der Sicherung wiederhergestellt', () async {
      file.writeAsStringSync(good);
      await guard.protect();
      file.writeAsStringSync(broken);
      expect(await guard.protect(), PrefsGuardResult.restored);
      expect(file.readAsStringSync(), good);
      expect(File('${file.path}.defekt').readAsStringSync(), broken);
    });
  }

  test('fehlende Datei kommt aus der Sicherung zurück', () async {
    file.writeAsStringSync(good);
    await guard.protect();
    file.deleteSync();
    expect(await guard.protect(), PrefsGuardResult.restored);
    expect(file.readAsStringSync(), good);
  });

  test('defekt und keine Sicherung: Datei wird entfernt, damit die App startet', () async {
    file.writeAsStringSync('{kaputt');
    expect(await guard.protect(), PrefsGuardResult.resetEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('defekte Sicherung wird nicht zurückgespielt', () async {
    File('${file.path}.bak').writeAsStringSync('');
    file.writeAsStringSync('');
    expect(await guard.protect(), PrefsGuardResult.resetEmpty);
  });
}
