import 'dart:math' as math;

import 'package:dartlab/core/lite.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_cloud.dart';
import 'history_seed.dart';
import 'pump_app.dart';

/// Adresse und Geheimnis, die „Ben“ seinem Vater gibt.
const liteUrl = 'dartlab-sync.ben.workers.dev';
final liteSecret = CloudSecret.generate(math.Random(7));

/// Einstellungen eines eingerichteten Geräts (wie nach der Einrichtung).
Map<String, Object> liteConnectedPrefs([CloudSecret? secret]) => {
      'sync.role': 'cloud',
      'sync.cloudUrl': 'https://$liteUrl',
      'sync.cloudSecret': (secret ?? liteSecret).text,
    };

/// Bens Gerät: Profil „Ben“, eine Handvoll Sessions, abgeglichen mit dem
/// Cloud-Speicher [cloud].
Future<CloudDevice> benInCloud(FakeCloud cloud, {CloudSecret? secret, DateTime? now}) async {
  final ben = CloudDevice(cloud, secret ?? liteSecret);
  final id = await ben.device.me();
  await ben.device.profiles.rename(id, 'Ben');
  await seedHistory(ben.device.games, id, now ?? DateTime.now());
  await ben.sync();
  return ben;
}

/// Die App als Lite-Variante auf einem Handy (360 × 800).
Future<ProviderContainer> pumpLite(
  WidgetTester tester, {
  FakeCloud? cloud,
  Size size = const Size(360, 800),
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
}) =>
    pumpApp(
      tester,
      size: size,
      prefs: prefs,
      overrides: [
        liteProvider.overrideWithValue(true),
        if (cloud != null) cloudHttpClientProvider.overrideWithValue(cloud.client),
        ...overrides,
      ],
    );

/// Wartet auf echte Zeit (Verschlüsselung, Datenbank) und zeichnet dann neu.
Future<void> settleLite(WidgetTester tester, {int ms = 600}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pumpAndSettle();
}

/// Aktueller Pfad des Routers.
String currentPath(ProviderContainer c) => c.read(routerProvider).routeInformationProvider.value.uri.path;

/// Tippt Adresse und Geheimnis in die Einrichtung und drückt „Verbinden“.
Future<void> fillAndConnect(WidgetTester tester, {String url = liteUrl, String? secret}) async {
  await tester.enterText(find.byKey(const Key('lite-setup-url')), url);
  await tester.enterText(find.byKey(const Key('lite-setup-secret')), secret ?? liteSecret.display);
  await tester.tap(find.byKey(const Key('lite-setup-connect')));
  await tester.pump();
}

/// Wartet (in echter Zeit), bis die Einrichtung fertig ist oder aufgibt.
Future<void> untilLeftSetup(WidgetTester tester, ProviderContainer c) async {
  for (var i = 0; i < 60 && currentPath(c) == '/willkommen'; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Eine Lite-App, die über die Einrichtung mit Bens Daten aus [cloud]
/// verbunden wurde (genau wie auf Vaters Handy).
Future<({ProviderContainer c, FakeCloud cloud, CloudDevice ben})> pumpLiteWithBen(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  Future<void> Function(CloudDevice ben)? prepare,
}) async {
  final cloud = FakeCloud();
  final ben = (await tester.runAsync(() => benInCloud(cloud)))!;
  if (prepare != null) {
    await tester.runAsync(() async {
      await prepare(ben);
      await ben.sync();
    });
  }
  final c = await pumpLite(tester, cloud: cloud, size: size, prefs: prefs, overrides: overrides);
  await fillAndConnect(tester);
  await untilLeftSetup(tester, c);
  expect(currentPath(c), '/statistik', reason: 'Einrichtung gelungen');
  // Der laufende Abgleich der App hat den ersten Durchlauf hinter sich.
  for (var i = 0; i < 80 && c.read(syncControllerProvider).lastSync == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return (c: c, cloud: cloud, ben: ben);
}

/// Baut die App ab (Sync-Zeitgeber, Datenbank), damit der Test ohne
/// ausstehende Zeitgeber endet.
Future<void> shutdownApp(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  // Die Datenbank schließt ihre Abfragen mit einem Zeitgeber.
  await tester.pump(const Duration(milliseconds: 50));
}
