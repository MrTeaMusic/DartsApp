import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/profiles/presentation/active_player.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_update.dart';
import '../helpers/lite_app.dart';

Future<void> openOptions(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Optionen', () {
    testWidgets('Verbindung, Update und Über, sonst nichts', (tester) async {
      final gh = FakeGitHub();
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester,
          overrides: updateOverrides(github: gh, host: FakeUpdateHost(platform: ReleasePlatform.android)));
      await openOptions(tester);
      expect(find.byKey(const Key('lite-settings')), findsOneWidget);
      expect(find.text('Verbindung'), findsOneWidget);
      // Bens Adresse und sein Geheimnis, so wie man sie abschreibt.
      expect(tester.widget<TextFormField>(find.byKey(const Key('sync-cloud-url-field'))).controller!.text, 'https://$liteUrl');
      expect(
        tester.widget<TextFormField>(find.byKey(const Key('sync-cloud-secret-field'))).controller!.text,
        liteSecret.display,
      );
      expect(find.textContaining('Zuletzt abgeglichen'), findsOneWidget);
      expect(find.byKey(const Key('sync-now')), findsOneWidget);
      expect(find.text('Jetzt abgleichen'), findsOneWidget);
      // Kein Hub, kein Heimnetz, kein neuer Tresor.
      for (final key in ['sync-role-off', 'sync-role-cloud', 'sync-role-hub', 'sync-role-client', 'sync-cloud-generate', 'sync-open-screen']) {
        expect(find.byKey(Key(key), skipOffstage: false), findsNothing, reason: key);
      }

      final about = find.byKey(const Key('lite-about-card'));
      await tester.scrollUntilVisible(
        about,
        300,
        scrollable: find.descendant(of: find.byKey(const Key('lite-settings')), matching: find.byType(Scrollable)).first,
      );
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('Über'), findsOneWidget);
      expect(find.text('DartLab Lite'), findsOneWidget);
      expect(find.text('Nur Ansicht. Spielen und Eintragen geschieht in der Haupt-App.'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('lite-about-version'))).data, 'Version 0.10.0 · Build 10');
      await shutdownApp(tester, c);
    });

    testWidgets('Jetzt abgleichen holt Neues von Ben', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      final db = c.read(appDatabaseProvider);
      final before = (await tester.runAsync(() => db.select(db.sessions).get()))!.length;
      // Ben spielt weiter.
      await tester.runAsync(() async {
        await ben.device.play(await ben.device.me(), minute: 42);
        await ben.sync();
      });
      await openOptions(tester);
      await tapVisible(tester, find.byKey(const Key('sync-now')));
      await settleLite(tester);
      expect((await tester.runAsync(() => db.select(db.sessions).get()))!.length, before + 1);
      expect(find.textContaining('Zuletzt abgeglichen'), findsOneWidget);
      await shutdownApp(tester, c);
    });

    testWidgets('Adresse oder Geheimnis ändern: ein unbekanntes Geheimnis wird abgefangen', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      await openOptions(tester);
      final vaults = cloud.vaults.length;
      await tester.enterText(find.byKey(const Key('sync-cloud-secret-field')), CloudSecret.generate().display);
      await tapVisible(tester, find.byKey(const Key('sync-now')));
      await settleLite(tester);
      expect(find.textContaining('noch keine Daten', skipOffstage: false), findsOneWidget);
      expect(CloudSecret.tryParse(c.read(settingsProvider).syncCloudSecret)?.text, liteSecret.text, reason: 'altes Geheimnis bleibt');
      expect(cloud.vaults, hasLength(vaults), reason: 'nie ein neuer Tresor');
      await shutdownApp(tester, c);
    });
  });

  group('Verbindung neu einrichten', () {
    testWidgets('mit Rückfrage; Abbrechen ändert nichts', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      await openOptions(tester);
      await tapVisible(tester, find.byKey(const Key('lite-reset-setup')));
      expect(find.byKey(const Key('lite-reset-dialog')), findsOneWidget);
      expect(find.text('Verbindung neu einrichten?'), findsOneWidget);
      expect(find.textContaining('Die bereits geladenen Daten bleiben auf dem Gerät'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).syncRole, SyncRole.cloud);
      expect(c.read(settingsProvider).syncCloudSecret, isNotEmpty);
      expect(currentPath(c), '/einstellungen');
      await shutdownApp(tester, c);
    });

    testWidgets('setzt zurück, führt zur Einrichtung und behält die Daten; neu verbinden klappt', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      final db = c.read(appDatabaseProvider);
      final before = (await tester.runAsync(() => db.select(db.sessions).get()))!.length;
      await openOptions(tester);
      await tapVisible(tester, find.byKey(const Key('lite-reset-setup')));
      await tester.tap(find.byKey(const Key('lite-reset-confirm')));
      await tester.pumpAndSettle();

      final s = c.read(settingsProvider);
      expect(s.syncRole, SyncRole.off);
      expect(s.syncCloudUrl, isEmpty);
      expect(s.syncCloudSecret, isEmpty);
      expect(currentPath(c), '/willkommen');
      expect(find.byKey(const Key('lite-setup')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect((await tester.runAsync(() => db.select(db.sessions).get()))!.length, before, reason: 'Daten bleiben auf dem Gerät');

      // Neu verbinden: keine doppelten Sessions.
      await tester.enterText(find.byKey(const Key('lite-setup-url')), liteUrl);
      await tester.enterText(find.byKey(const Key('lite-setup-secret')), liteSecret.display);
      await tester.tap(find.byKey(const Key('lite-setup-connect')));
      for (var i = 0; i < 60 && currentPath(c) == '/willkommen'; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(currentPath(c), '/statistik');
      expect((await tester.runAsync(() => db.select(db.sessions).get()))!.length, before);
      expect(c.read(activePlayerProvider)!.name, 'Ben');
      await shutdownApp(tester, c);
    });
  });

  group('Mehrere Profile', () {
    testWidgets('Auswahl in den Optionen, Standard ist Bens Hauptprofil', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester, prepare: (ben) async {
        final anna = await ben.device.profiles.create('Anna');
        await ben.device.play(anna, minute: 7);
      });
      expect(c.read(activePlayerProvider)!.name, 'Ben');
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Ben')), findsOneWidget);
      await openOptions(tester);
      expect(find.text('Statistik von', skipOffstage: false), findsOneWidget);
      final choice = find.byKey(const Key('lite-profile-card'));
      await tester.scrollUntilVisible(
        choice,
        300,
        scrollable: find.descendant(of: find.byKey(const Key('lite-settings')), matching: find.byType(Scrollable)).first,
      );
      expect(choice, findsOneWidget);
      expect(find.descendant(of: choice, matching: find.byType(RadioListTile<int>)), findsNWidgets(2));
      // Nur auswählen, nichts anlegen, umbenennen oder löschen.
      expect(find.byKey(const Key('profile-add')), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tapVisible(tester, find.descendant(of: choice, matching: find.text('Anna')));
      expect(c.read(activePlayerProvider)!.name, 'Anna');
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Statistik')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Anna')), findsOneWidget);
      await shutdownApp(tester, c);
    });

    testWidgets('mit einem Profil gibt es keine Auswahl', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      await openOptions(tester);
      expect(find.byKey(const Key('lite-profile-card')), findsNothing);
      expect(find.text('Statistik von', skipOffstage: false), findsNothing);
      await shutdownApp(tester, c);
    });
  });
}
