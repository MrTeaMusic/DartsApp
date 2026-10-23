import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/lite/domain/lite_gate.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('die Lite-Pfade sind die der Router-Tabelle', () {
    expect(LiteRoutes.stats, Routes.stats);
    expect(LiteRoutes.settings, Routes.settings);
    expect(LiteRoutes.watch, Routes.watch);
  });

  group('liteIsConnected', () {
    const ready = AppSettings(syncRole: SyncRole.cloud, syncCloudUrl: 'https://x.example', syncCloudSecret: 'ABC');

    test('nur mit Rolle Cloud, Adresse und Geheimnis', () {
      expect(liteIsConnected(const AppSettings()), isFalse);
      expect(liteIsConnected(ready), isTrue);
      expect(liteIsConnected(ready.copyWith(syncRole: SyncRole.off)), isFalse);
      expect(liteIsConnected(ready.copyWith(syncRole: SyncRole.client)), isFalse);
      expect(liteIsConnected(ready.copyWith(syncCloudUrl: '  ')), isFalse);
      expect(liteIsConnected(ready.copyWith(syncCloudSecret: '')), isFalse);
    });
  });

  group('liteRedirect', () {
    test('ohne Einrichtung gibt es nur die Einrichtung', () {
      expect(liteRedirect('/willkommen', connected: false), isNull);
      for (final path in ['/', '/statistik', '/zuschauen', '/einstellungen', '/training', '/gibt-es-nicht']) {
        expect(liteRedirect(path, connected: false), '/willkommen', reason: path);
      }
    });

    test('mit Einrichtung nur Live, Statistik, Verlauf, Details und Optionen', () {
      for (final path in [
        '/zuschauen',
        '/zuschauen/',
        '/statistik',
        '/statistik/',
        '/statistik/verlauf',
        '/statistik/verlauf/12',
        '/statistik/verlauf/12/',
        '/einstellungen',
        '/einstellungen/',
      ]) {
        expect(liteRedirect(path, connected: true), isNull, reason: path);
      }
      for (final path in [
        '/',
        '/training',
        '/training/x01',
        '/training/plaene',
        '/board',
        '/spiel',
        '/einstellungen/debug',
        '/willkommen',
        '/statistikfremd',
        '/zuschauen/mehr',
        '/zuschauenfremd',
        '/statistik/gibt-es-nicht',
        '/statistik/verlauf/12/mehr',
        '/einstellungen/anderes',
        '/gibt-es-nicht',
      ]) {
        expect(liteRedirect(path, connected: true), '/statistik', reason: path);
      }
    });
  });
}
