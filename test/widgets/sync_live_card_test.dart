import 'dart:math' as math;

import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/live_remote/data/live_pusher.dart';
import 'package:dartlab/features/live_remote/presentation/live_push_controller.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_cloud.dart';
import '../helpers/lite_app.dart' show shutdownApp;
import '../helpers/pump_app.dart';

final secret = CloudSecret.generate(math.Random(41));
const url = 'https://dartlab-sync.ben.workers.dev';

Map<String, Object> cloudPrefs({bool live = false}) => {
      'sync.role': 'cloud',
      'sync.cloudUrl': url,
      'sync.cloudSecret': secret.text,
      if (live) 'sync.liveShare': true,
    };

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

/// Wartet auf echte Zeit (Verschlüsselung) und zeichnet neu.
Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pumpAndSettle();
}

String statusText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('sync-live-status'))).data!;

void main() {
  late FakeCloud cloud;
  setUp(() => cloud = FakeCloud());

  Future<ProviderContainer> open(WidgetTester tester, Map<String, Object> prefs) async {
    final c = await pumpApp(tester, prefs: prefs, overrides: [cloudHttpClientProvider.overrideWithValue(cloud.client)]);
    await openSync(tester);
    return c;
  }

  testWidgets('Cloud-Rolle: Schalter ist standardmäßig aus, mit einem Satz Erklärung, ohne Statuszeile', (tester) async {
    final c = await open(tester, cloudPrefs());
    final sw = find.byKey(const Key('sync-live-switch'));
    await tester.ensureVisible(sw);
    await tester.pumpAndSettle();
    expect(sw, findsOneWidget);
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    expect(find.text('Live übers Internet zeigen'), findsOneWidget);
    // Ein Satz: Zuschauer sehen das Spiel, aber nur mit dem Geheimnis.
    expect(find.text('Zuschauer sehen dein laufendes Spiel live, aber nur mit deinem Geheimnis.'), findsOneWidget);
    expect(find.byKey(const Key('sync-live-status')), findsNothing);
    expect(c.read(settingsProvider).liveShare, isFalse);
    expect(c.read(livePushControllerProvider).status, LivePushStatus.off);
    await settle(tester);
    expect(cloud.requests.where((r) => r.contains('/v1/live')), isEmpty);
    expect(cloud.requests.where((r) => r.contains('hello')), isEmpty, reason: 'nur der normale Abgleich ist unterwegs: ${cloud.requests}');
    expect(cloud.livePuts, 0);
    await shutdownApp(tester, c);
  });

  testWidgets('andere Rollen haben keinen Schalter', (tester) async {
    final c = await open(tester, const {});
    for (final role in ['off', 'client', 'hub']) {
      final f = find.byKey(Key('sync-role-$role'), skipOffstage: false);
      if (f.evaluate().isEmpty) continue; // Hub gibt es nur am Desktop
      await tapVisible(tester, f);
      expect(find.byKey(const Key('sync-live-switch')), findsNothing, reason: role);
    }
    await tapVisible(tester, find.byKey(const Key('sync-role-cloud')));
    expect(find.byKey(const Key('sync-live-switch')), findsOneWidget);
    await shutdownApp(tester, c);
  });

  testWidgets('einschalten: Statuszeile "Live ist an", Einstellung gespeichert, noch nichts gesendet', (tester) async {
    final c = await open(tester, cloudPrefs());
    await tapVisible(tester, find.byKey(const Key('sync-live-switch')));
    expect(c.read(settingsProvider).liveShare, isTrue);
    await settle(tester);
    expect(find.byKey(const Key('sync-live-status')), findsOneWidget);
    expect(statusText(tester), 'Live ist an. Gesendet wird, sobald ein Spiel läuft.');
    expect(cloud.livePuts, 0, reason: 'ohne Spiel wird nichts gesendet');
    expect(c.read(livePushControllerProvider).status, LivePushStatus.waiting);

    // Wieder aus: Statuszeile weg, nichts mehr unterwegs.
    await tapVisible(tester, find.byKey(const Key('sync-live-switch')));
    expect(c.read(settingsProvider).liveShare, isFalse);
    expect(find.byKey(const Key('sync-live-status')), findsNothing);
    await settle(tester);
    expect(c.read(livePushControllerProvider).status, LivePushStatus.off);
    await shutdownApp(tester, c);
  });

  testWidgets('bereits an gespeichert: Schalter steht auf an', (tester) async {
    final c = await open(tester, cloudPrefs(live: true));
    final sw = find.byKey(const Key('sync-live-switch'));
    await tester.ensureVisible(sw);
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    await settle(tester);
    expect(find.byKey(const Key('sync-live-status')), findsOneWidget);
    await shutdownApp(tester, c);
  });

  testWidgets('alter Cloud-Speicher: Hinweis, dass er aktualisiert werden muss', (tester) async {
    cloud.liveSupported = false;
    final c = await open(tester, cloudPrefs(live: true));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('sync-live-status')));
    expect(statusText(tester), startsWith('Der Cloud-Speicher muss aktualisiert werden, damit Live geht.'));
    expect(statusText(tester), contains('cloud/README.md'));
    expect(tester.widget<Text>(find.byKey(const Key('sync-live-status'))).style?.color, isNotNull, reason: 'als Fehler eingefärbt');
    expect(cloud.livePuts, 0);
    await shutdownApp(tester, c);
  });

  testWidgets('kein Netz: Fehlertext, die App läuft weiter', (tester) async {
    cloud.hold = (req) {
      if (req.url.path == '/v1/hello') throw http.ClientException('offline');
      return null;
    };
    final c = await open(tester, cloudPrefs(live: true));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('sync-live-status')));
    expect(statusText(tester), startsWith('Live: Keine Verbindung zum Cloud-Speicher.'));
    expect(statusText(tester), contains('läuft ungestört weiter'));
    expect(tester.takeException(), isNull);
    await shutdownApp(tester, c);
  });

  testWidgets('Schalter an, aber ohne Adresse und Geheimnis: Hinweis', (tester) async {
    final c = await open(tester, const {'sync.role': 'cloud', 'sync.liveShare': true});
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('sync-live-status')));
    expect(statusText(tester), startsWith('Live braucht Adresse und Geheimnis'));
    expect(cloud.requests, isEmpty);
    await shutdownApp(tester, c);
  });

  testWidgets('ohne Schalter ändert sich nichts: gleiche Anfragen wie ohne die Funktion', (tester) async {
    final c = await open(tester, cloudPrefs());
    await settle(tester, 800);
    final paths = cloud.requests.map((r) => r.split(' ').last.split('?').first).toSet();
    expect(paths.every((p) => p == '/v1/hello' || p == '/v1/meta' || p.startsWith('/v1/s/')), isTrue, reason: '$paths');
    await shutdownApp(tester, c);
  });
}
