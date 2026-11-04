import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die iOS-App-Kennung (Bundle Identifier) entscheidet, welche Daten eine
/// App auf dem iPhone sieht. Stand sie als lokale Änderung im Xcode-Projekt,
/// hat ein git pull mit Konflikt oder ein neuer Klon sie zurückgesetzt, und
/// das Update startete ohne Daten und Einstellungen. Diese Tests halten fest,
/// dass die Kennung nur noch aus den xcconfig-Dateien plus der lokalen,
/// von git ausgenommenen Signing.local.xcconfig kommt.
void main() {
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  /// Build-Einstellungen der Runner-Konfigurationen (Debug, Release, Profile).
  List<String> runnerConfigs() {
    final blocks = RegExp(r'/\* (Debug|Release|Profile) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};', dotAll: true)
        .allMatches(pbxproj)
        .map((m) => m.group(2)!)
        .where((b) => b.contains('INFOPLIST_FILE = Runner/Info.plist'))
        .toList();
    return blocks;
  }

  test('Runner-Target setzt Kennung und Team nicht im Xcode-Projekt', () {
    final configs = runnerConfigs();
    expect(configs, hasLength(3), reason: 'Debug, Release und Profile des Runner-Targets');
    for (final c in configs) {
      expect(c, isNot(contains('PRODUCT_BUNDLE_IDENTIFIER')),
          reason: 'Sonst überschreibt das Projekt die eigene Kennung aus Signing.local.xcconfig');
      expect(c, isNot(contains('DEVELOPMENT_TEAM')));
    }
  });

  test('Runner-Konfigurationen bauen auf Debug.xcconfig bzw. Release.xcconfig auf', () {
    final refs = RegExp(r'baseConfigurationReference = \w+ /\* (\w+)\.xcconfig \*/;(?:(?!\n\t\t\};).)*INFOPLIST_FILE = Runner/Info\.plist',
            dotAll: true)
        .allMatches(pbxproj)
        .map((m) => m.group(1))
        .toList();
    expect(refs, unorderedEquals(['Debug', 'Release', 'Release']));
  });

  for (final name in ['Debug', 'Release']) {
    test('$name.xcconfig: Vorgabe-Kennung, danach die lokale Datei', () {
      final lines = File('ios/Flutter/$name.xcconfig').readAsLinesSync().map((l) => l.trim()).toList();
      final defaultLine = lines.indexOf('PRODUCT_BUNDLE_IDENTIFIER = de.dartlab.dartlab');
      final includeLine = lines.indexOf('#include? "Signing.local.xcconfig"');
      expect(defaultLine, isNonNegative);
      // Später gesetzte Werte gewinnen, die lokale Datei muss also danach kommen.
      expect(includeLine, greaterThan(defaultLine));
    });
  }

  test('Signing.local.xcconfig ist von git ausgenommen', () {
    final ignore = File('ios/.gitignore').readAsLinesSync().map((l) => l.trim());
    expect(ignore, contains('Flutter/Signing.local.xcconfig'));
  });

  test('Helfer-Skripte sind da und ausführbar', () {
    for (final path in ['tools/ios/signing.sh', 'tools/ios/update.sh']) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: path);
      if (!Platform.isWindows) {
        expect(f.statSync().mode & 0x40, isNot(0), reason: '$path muss ausführbar sein');
      }
    }
  });
}
