import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_cloud.dart';
import '../helpers/pump_app.dart';

Future<void> openSync(WidgetTester tester) async {
  await tester.tap(find.text('Optionen').first);
  await tester.pumpAndSettle();
  final role = find.byKey(const Key('sync-role-off'));
  await tester.scrollUntilVisible(role, 300, scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(role);
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> roleOff(WidgetTester tester) async {
  final off = find.byKey(const Key('sync-role-off'));
  await tester.scrollUntilVisible(off, -300, scrollable: find.byType(Scrollable).last);
  await tapVisible(tester, off);
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Cloud: neues Geheimnis erzeugen, verbinden und abgleichen', (tester) async {
    final cloud = FakeCloud();
    final c = await pumpApp(tester, overrides: [cloudHttpClientProvider.overrideWithValue(cloud.client)]);
    await openSync(tester);
    await tapVisible(tester, find.byKey(const Key('sync-role-cloud')));
    expect(c.read(settingsProvider).syncRole, SyncRole.cloud);
    expect(find.text('Noch nicht abgeglichen.'), findsOneWidget);
    expect(find.textContaining('nur verschlüsselte Daten'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sync-cloud-url-field')), 'dartlab-sync.ben.workers.dev');
    await tapVisible(tester, find.byKey(const Key('sync-cloud-generate')));
    expect(find.byKey(const Key('sync-cloud-generated')), findsOneWidget);
    final shown = tester.widget<TextFormField>(find.byKey(const Key('sync-cloud-secret-field'))).controller!.text;
    expect(CloudSecret.tryParse(shown), isNotNull);

    await tapVisible(tester, find.byKey(const Key('sync-now')));
    await settle(tester);
    await settle(tester);
    final s = c.read(settingsProvider);
    expect(s.syncCloudUrl, 'https://dartlab-sync.ben.workers.dev');
    expect(CloudSecret.tryParse(s.syncCloudSecret)?.display, shown);
    expect(find.textContaining('Zuletzt abgeglichen', skipOffstage: false), findsOneWidget);
    expect(cloud.vaults, hasLength(1), reason: 'Tresor wurde angelegt');

    await roleOff(tester);
    expect(find.byKey(const Key('sync-cloud-url-field')), findsNothing);
  });

  testWidgets('Cloud: ein Geheimnis ohne Tresor wird abgefangen, nichts wird gespeichert', (tester) async {
    final cloud = FakeCloud();
    final c = await pumpApp(tester, overrides: [cloudHttpClientProvider.overrideWithValue(cloud.client)]);
    await openSync(tester);
    await tapVisible(tester, find.byKey(const Key('sync-role-cloud')));
    await tester.enterText(find.byKey(const Key('sync-cloud-url-field')), 'https://x.example');
    await tester.enterText(find.byKey(const Key('sync-cloud-secret-field')), CloudSecret.generate().display);
    await tapVisible(tester, find.byKey(const Key('sync-now')));
    await settle(tester);
    expect(find.textContaining('noch keine Daten', skipOffstage: false), findsOneWidget);
    expect(c.read(settingsProvider).syncCloudSecret, isEmpty);
    expect(cloud.vaults, isEmpty);
    await roleOff(tester);
  });

  testWidgets('Cloud: ungültige Eingaben und falsche Adresse', (tester) async {
    final cloud = FakeCloud()..override = (_) => throw http.ClientException('offline');
    final c = await pumpApp(tester, overrides: [cloudHttpClientProvider.overrideWithValue(cloud.client)]);
    await openSync(tester);
    await tapVisible(tester, find.byKey(const Key('sync-role-cloud')));
    await tapVisible(tester, find.byKey(const Key('sync-now')));
    expect(find.text('Adresse des Cloud-Speichers eintragen'), findsOneWidget);
    expect(find.textContaining('26 Zeichen'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sync-cloud-url-field')), 'x.example');
    await tester.enterText(find.byKey(const Key('sync-cloud-secret-field')), CloudSecret.generate().display);
    await tapVisible(tester, find.byKey(const Key('sync-now')));
    await settle(tester);
    expect(c.read(settingsProvider).syncCloudSecret, isEmpty);
    expect(find.textContaining('Cloud-Speicher nicht erreichbar', skipOffstage: false), findsOneWidget);
    await roleOff(tester);
  });
}
