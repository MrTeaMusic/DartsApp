import 'dart:async';

import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/profiles/presentation/active_player.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_cloud.dart';
import '../helpers/lite_app.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Weiche am Start', () {
    testWidgets('ohne Einrichtung: Einrichtung ohne Navigationsleiste', (tester) async {
      final c = await pumpLite(tester, cloud: FakeCloud());
      expect(currentPath(c), '/willkommen');
      expect(find.byKey(const Key('lite-welcome-title')), findsOneWidget);
      expect(find.text('Willkommen bei DartLab Lite'), findsOneWidget);
      expect(find.textContaining('Frag Ben nach der Adresse und dem Geheimnis'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      // Auch ein Sprung auf die Statistik landet wieder dort.
      c.read(routerProvider).go(Routes.stats);
      await tester.pumpAndSettle();
      expect(currentPath(c), '/willkommen');
      c.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      expect(currentPath(c), '/willkommen');
    });

    testWidgets('mit Einrichtung: gleich die Statistik', (tester) async {
      final c = await pumpLite(tester, cloud: FakeCloud(), prefs: liteConnectedPrefs());
      expect(currentPath(c), '/statistik');
      expect(find.byKey(const Key('stats-tabs')), findsOneWidget);
      expect(find.byKey(const Key('lite-setup')), findsNothing);
      await shutdownApp(tester, c);
    });

    testWidgets('halb eingerichtet (Rolle ohne Geheimnis) fragt noch einmal', (tester) async {
      final c = await pumpLite(tester, cloud: FakeCloud(), prefs: {'sync.role': 'cloud', 'sync.cloudUrl': 'https://x.example'});
      expect(currentPath(c), '/willkommen');
      await shutdownApp(tester, c);
    });

    testWidgets('die volle App kennt die Einrichtung nicht', (tester) async {
      // Ohne den Lite-Schalter bleibt alles beim Alten.
      final c = await pumpApp(tester);
      expect(currentPath(c), '/');
      expect(find.byType(NavigationRail), findsOneWidget);
      c.read(routerProvider).go('/willkommen');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lite-setup')), findsNothing);
    });
  });

  group('Verbinden', () {
    testWidgets('Eingaben werden geprüft, bevor etwas das Netz berührt', (tester) async {
      final cloud = FakeCloud();
      var requests = 0;
      cloud.override = (_) {
        requests++;
        return null;
      };
      await pumpLite(tester, cloud: cloud);
      await tester.tap(find.byKey(const Key('lite-setup-connect')));
      await tester.pumpAndSettle();
      expect(find.text('Adresse des Cloud-Speichers eintragen'), findsOneWidget);
      expect(find.textContaining('26 Zeichen'), findsOneWidget);
      await fillAndConnect(tester, url: 'zwei wörter', secret: 'zu kurz');
      await tester.pumpAndSettle();
      expect(find.text('Adresse des Cloud-Speichers eintragen'), findsOneWidget);
      expect(requests, 0);
    });

    testWidgets('erfolgreich: Fortschritt, Daten von Ben, dann die Statistik', (tester) async {
      final cloud = FakeCloud();
      await tester.runAsync(() => benInCloud(cloud));
      final checking = Completer<void>();
      final loading = Completer<void>();
      cloud.hold = (req) {
        if (req.url.path == '/v1/hello') return checking.future;
        if (req.url.path.startsWith('/v1/s/')) return loading.future;
        return null;
      };
      final c = await pumpLite(tester, cloud: cloud);
      expect(c.read(settingsProvider).syncRole, SyncRole.off);

      // Groß-/Kleinschreibung, Striche und ein Schrägstrich am Ende sind egal.
      await fillAndConnect(tester, url: 'https://$liteUrl/', secret: liteSecret.display.toLowerCase().replaceAll('-', ' '));
      expect(find.byKey(const Key('lite-setup-progress')), findsOneWidget);
      expect(find.text('Verbindung wird geprüft …'), findsOneWidget);
      // Während des Ladens ist nichts mehr bedienbar.
      expect(tester.widget<FilledButton>(find.byKey(const Key('lite-setup-connect'))).onPressed, isNull);
      expect(tester.widget<TextFormField>(find.byKey(const Key('lite-setup-url'))).enabled, isFalse);

      checking.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.text('Daten werden geladen …'), findsOneWidget);
      expect(find.textContaining('Bitte die App offen lassen'), findsOneWidget);
      expect(currentPath(c), '/willkommen');
      expect(c.read(settingsProvider).syncRole, SyncRole.off, reason: 'gespeichert wird erst nach dem Laden');

      loading.complete();
      await untilLeftSetup(tester, c);
      expect(currentPath(c), '/statistik');
      final s = c.read(settingsProvider);
      expect(s.syncRole, SyncRole.cloud);
      expect(s.syncCloudUrl, 'https://$liteUrl');
      expect(CloudSecret.tryParse(s.syncCloudSecret)?.text, liteSecret.text);
      expect(find.byType(NavigationBar), findsOneWidget);

      // Bens Daten sind da, unter Bens Namen: Das Standardprofil ist Bens Hauptprofil.
      final players = (await tester.runAsync(c.read(profileRepositoryProvider).players))!;
      expect(players, hasLength(1), reason: 'das leere „Ich“ ist mit Bens Profil zusammengeführt');
      expect(players.single.name, 'Ben');
      expect(players.single.uid, 'default-player');
      expect(players.single.isDefault, isTrue);
      expect(c.read(activePlayerProvider)!.name, 'Ben');
      await settleLite(tester);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Ben')), findsOneWidget);
      expect(find.byKey(const Key('stat-average')), findsOneWidget);
      expect(find.text('Noch keine Daten'), findsNothing);
      await shutdownApp(tester, c);
    });

    testWidgets('Neustart behält die Einrichtung', (tester) async {
      final cloud = FakeCloud();
      await tester.runAsync(() => benInCloud(cloud));
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await untilLeftSetup(tester, c);
      expect(currentPath(c), '/statistik');
      // Die gespeicherten Einstellungen sind das, was beim nächsten Start gelesen wird.
      final saved = c.read(sharedPreferencesProvider);
      final prefs = {for (final k in saved.getKeys()) k: saved.get(k)!};
      await shutdownApp(tester, c);

      final again = await pumpLite(tester, cloud: cloud, prefs: prefs);
      expect(currentPath(again), '/statistik');
      expect(find.byKey(const Key('lite-setup')), findsNothing);
      await shutdownApp(tester, again);
    });

    testWidgets('Einfügen-Knopf übernimmt das Geheimnis aus der Zwischenablage', (tester) async {
      await pumpLite(tester, cloud: FakeCloud());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': '  ${liteSecret.display.toLowerCase()}\n'};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byKey(const Key('lite-setup-paste')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(find.byKey(const Key('lite-setup-secret')));
      expect(CloudSecret.tryParse(field.controller!.text)?.text, liteSecret.text);
    });
  });

  group('Fehler: es wird nichts gespeichert und nie ein Tresor angelegt', () {
    Future<void> expectStuck(WidgetTester tester, ProviderContainer c, FakeCloud cloud, String message) async {
      await tester.pumpAndSettle();
      expect(currentPath(c), '/willkommen');
      expect(find.byKey(const Key('lite-setup-error')), findsOneWidget);
      expect(find.textContaining(message), findsOneWidget);
      expect(find.byKey(const Key('lite-setup-progress')), findsNothing);
      final s = c.read(settingsProvider);
      expect(s.syncRole, SyncRole.off);
      expect(s.syncCloudUrl, isEmpty);
      expect(s.syncCloudSecret, isEmpty);
      expect(cloud.vaults, isEmpty, reason: 'Lite legt nie einen Tresor an');
      expect(cloud.metaPuts, 0);
      // Weitermachen ist möglich: Die Felder sind wieder bedienbar.
      expect(tester.widget<FilledButton>(find.byKey(const Key('lite-setup-connect'))).onPressed, isNotNull);
    }

    testWidgets('kein Tresor (falsches Geheimnis oder Ben hat noch nie abgeglichen)', (tester) async {
      final cloud = FakeCloud();
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await settleLite(tester);
      await expectStuck(tester, c, cloud, 'Zu diesem Geheimnis gibt es dort keine Daten');
      expect(find.textContaining('muss Ben erst einmal in seiner App abgleichen'), findsOneWidget);
      // Tippen löscht die Meldung.
      await tester.enterText(find.byKey(const Key('lite-setup-secret')), CloudSecret.generate().display);
      await tester.pump();
      expect(find.byKey(const Key('lite-setup-error')), findsNothing);
    });

    testWidgets('anderes Geheimnis als Bens Tresor', (tester) async {
      final cloud = FakeCloud();
      await tester.runAsync(() => benInCloud(cloud));
      final vaultsBefore = cloud.vaults.length;
      final putsBefore = cloud.metaPuts;
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester, secret: CloudSecret.generate().display);
      await settleLite(tester);
      await tester.pumpAndSettle();
      expect(currentPath(c), '/willkommen');
      expect(find.textContaining('Zu diesem Geheimnis gibt es dort keine Daten'), findsOneWidget);
      expect(c.read(settingsProvider).syncRole, SyncRole.off);
      expect(cloud.vaults, hasLength(vaultsBefore));
      expect(cloud.metaPuts, putsBefore);
    });

    testWidgets('Server lehnt das Geheimnis ab', (tester) async {
      final cloud = FakeCloud()
        ..override = (req) => req.url.path == '/v1/hello' ? null : http.Response('{"error":"unauthorized"}', 401, headers: {'x-dartlab-cloud': '1'});
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await settleLite(tester);
      await expectStuck(tester, c, cloud, 'lehnt das Geheimnis ab');
    });

    testWidgets('nicht erreichbar', (tester) async {
      final cloud = FakeCloud()..override = (_) => throw http.ClientException('offline');
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await settleLite(tester);
      await expectStuck(tester, c, cloud, 'Der Cloud-Speicher ist nicht erreichbar');
    });

    testWidgets('unter der Adresse läuft etwas anderes', (tester) async {
      final cloud = FakeCloud()..override = (_) => http.Response('<html>hallo</html>', 200);
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester, url: 'example.com');
      await settleLite(tester);
      await expectStuck(tester, c, cloud, 'antwortet kein DartLab-Cloud-Speicher');
    });

    testWidgets('Server-Fehler', (tester) async {
      final cloud = FakeCloud()
        ..override = (req) => req.url.path == '/v1/hello'
            ? null
            : http.Response('{"error":"db down"}', 500, headers: {'x-dartlab-cloud': '1'});
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await settleLite(tester);
      await expectStuck(tester, c, cloud, 'Der Cloud-Speicher meldet einen Fehler: db down');
    });

    testWidgets('Daten des Tresors lassen sich nicht öffnen: nichts wird gespeichert', (tester) async {
      final cloud = FakeCloud();
      await tester.runAsync(() => benInCloud(cloud));
      // Der Tresor ist vorhanden, aber die Meta kaputt (z. B. verändert).
      for (final v in cloud.vaults.values) {
        v.meta = 'AAAA${v.meta}';
      }
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await settleLite(tester);
      await tester.pumpAndSettle();
      expect(currentPath(c), '/willkommen');
      expect(find.textContaining('lassen sich mit diesem Geheimnis nicht öffnen'), findsOneWidget);
      expect(c.read(settingsProvider).syncCloudSecret, isEmpty);
    });

    testWidgets('ein Fehler beim Laden hinterlässt keine halbe Einrichtung', (tester) async {
      final cloud = FakeCloud();
      await tester.runAsync(() => benInCloud(cloud));
      var failSessions = true;
      cloud.override = (req) => failSessions && req.url.path.startsWith('/v1/s/')
          ? http.Response('{"error":"busy"}', 503, headers: {'x-dartlab-cloud': '1'})
          : null;
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await settleLite(tester);
      await tester.pumpAndSettle();
      expect(currentPath(c), '/willkommen');
      expect(find.byKey(const Key('lite-setup-error')), findsOneWidget);
      expect(c.read(settingsProvider).syncRole, SyncRole.off);
      // Zweiter Versuch klappt.
      failSessions = false;
      await tester.tap(find.byKey(const Key('lite-setup-connect')));
      await untilLeftSetup(tester, c);
      expect(currentPath(c), '/statistik');
      await shutdownApp(tester, c);
    });
  });

  group('Hauptprofil', () {
    testWidgets('liegen Bens Daten bei einem anderen Profil, wird dieses gezeigt', (tester) async {
      // Bens Standardprofil ist leer; seine Sessions gehören „Ben“.
      final cloud = FakeCloud();
      await tester.runAsync(() async {
        final ben = CloudDevice(cloud, liteSecret);
        final other = await ben.device.profiles.create('Ben');
        await ben.device.play(other, minute: 1);
        await ben.device.play(other, minute: 2);
        await ben.sync();
      });
      final c = await pumpLite(tester, cloud: cloud);
      await fillAndConnect(tester);
      await untilLeftSetup(tester, c);
      expect(currentPath(c), '/statistik');
      expect(c.read(activePlayerProvider)!.name, 'Ben');
      await shutdownApp(tester, c);
    });
  });
}
