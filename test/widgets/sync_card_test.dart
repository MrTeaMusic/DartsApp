import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets('Client: Adresse und Code eintragen, Fehler wird angezeigt', (tester) async {
    final c = await pumpApp(tester, prefs: {'settings.autodartsHost': '192.168.178.20'});
    await openSync(tester);
    expect(find.byKey(const Key('sync-role-hub')), findsNothing, reason: 'Hub nur auf dem Desktop');

    await tapVisible(tester, find.byKey(const Key('sync-role-client')));
    expect(c.read(settingsProvider).syncRole, SyncRole.client);
    expect(find.text('Noch nicht abgeglichen.'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('sync-use-autodarts-host')));
    await tester.enterText(find.byKey(const Key('sync-code-field')), '123456');
    await tapVisible(tester, find.byKey(const Key('sync-now')));
    expect(c.read(settingsProvider).syncHost, '192.168.178.20');
    expect(c.read(settingsProvider).syncKey, '123456');

    // In Widget-Tests antwortet jeder Server mit 400 und ohne DartLab-Kennung.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.textContaining('kein DartLab-Hub'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('sync-role-off')));
    expect(find.byKey(const Key('sync-host-field')), findsNothing);
  });

  testWidgets('Hub zeigt Code und startet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final c = await pumpApp(tester, prefs: {'sync.port': 0});
    await openSync(tester);
    await tapVisible(tester, find.byKey(const Key('sync-role-hub')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    final key = c.read(settingsProvider).syncKey;
    expect(key, matches(RegExp(r'^\d{6}$')));
    expect(find.text(key), findsOneWidget);
    expect(find.textContaining('Hub läuft'), findsOneWidget);
    expect(find.textContaining('Windows-Firewall'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('sync-new-code')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).syncKey, isNot(key));

    await tapVisible(tester, find.byKey(const Key('sync-role-off')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    debugDefaultTargetPlatformOverride = null;
  });
}
