import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:dartlab/features/sync/data/sync_server.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/sync_device.dart';

Future<ProviderContainer> containerFor(Device d, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    appDatabaseProvider.overrideWithValue(d.db),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> until(bool Function() done, {Duration max = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Die Test-Bindung ersetzt HttpClient durch eine Attrappe; hier wird über
  // localhost wirklich gesprochen.
  HttpOverrides.global = null;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('Einstellungen für den Sync werden gespeichert und geladen', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await const AppSettings(syncRole: SyncRole.client, syncHost: '192.168.1.5', syncPort: 4000, syncKey: '424242').save(sp);
    final s = AppSettings.load(sp);
    expect(s.syncRole, SyncRole.client);
    expect(s.syncHost, '192.168.1.5');
    expect(s.syncPort, 4000);
    expect(s.syncKey, '424242');
    expect(const AppSettings().syncRole, SyncRole.off);
    expect(newSyncKey(), matches(RegExp(r'^\d{6}$')));

    await const AppSettings(syncRole: SyncRole.cloud, syncCloudUrl: 'https://x.example', syncCloudSecret: 'ABC').save(sp);
    final c = AppSettings.load(sp);
    expect(c.syncRole, SyncRole.cloud);
    expect(c.syncCloudUrl, 'https://x.example');
    expect(c.syncCloudSecret, 'ABC');
    expect(const AppSettings().syncCloudUrl, isEmpty);
  });

  group('Client', () {
    late Device hub;
    late Device phone;
    late SyncServer server;
    setUp(() async {
      hub = Device();
      phone = Device();
      server = SyncServer(hub.store, key: '111111');
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      SyncController.debounce = const Duration(milliseconds: 50);
    });
    tearDown(() async {
      await server.dispose();
      await hub.db.close();
      await phone.db.close();
    });

    test('gleicht beim Start und nach einem Spielende von selbst ab', () async {
      await hub.play(await hub.me(), minute: 1);
      final c = await containerFor(phone, {
        'sync.role': 'client',
        'sync.host': '127.0.0.1',
        'sync.port': server.port!,
        'sync.key': '111111',
      });
      c.listen(syncControllerProvider, (_, _) {});
      await until(() => c.read(syncControllerProvider).lastSync != null);
      expect(c.read(syncControllerProvider).lastReport!.received, 1);
      expect(await phone.sessions(), hasLength(1));

      // Neues Spiel auf dem Telefon landet ohne Zutun auf dem Hub.
      await phone.play(await phone.me(), minute: 2);
      await until(() => c.read(syncControllerProvider).lastReport?.sent == 1);
      expect(await hub.sessions(), hasLength(2));
    });

    test('falscher Code wird gemeldet', () async {
      final c = await containerFor(phone, {
        'sync.role': 'client',
        'sync.host': '127.0.0.1',
        'sync.port': server.port!,
        'sync.key': '999999',
      });
      c.listen(syncControllerProvider, (_, _) {});
      await until(() => c.read(syncControllerProvider).failure != null);
      expect(c.read(syncControllerProvider).failure, SyncFailure.wrongKey);
    });

    test('ohne Adresse passiert nichts', () async {
      final c = await containerFor(phone, {'sync.role': 'client', 'sync.key': '1'});
      c.listen(syncControllerProvider, (_, _) {});
      await c.read(syncControllerProvider.notifier).syncNow();
      expect(c.read(syncControllerProvider).lastSync, isNull);
      expect(c.read(syncControllerProvider).failure, isNull);
    });
  });

  group('Hub', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('erzeugt einen Code, startet und nimmt Abgleiche an', () async {
      final hub = Device();
      final phone = Device();
      addTearDown(hub.db.close);
      addTearDown(phone.db.close);
      final free = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = free.port;
      await free.close();

      final c = await containerFor(hub, {'sync.role': 'hub', 'sync.port': port});
      c.listen(syncControllerProvider, (_, _) {});
      await until(() => c.read(syncControllerProvider).hubRunning);
      final key = c.read(settingsProvider).syncKey;
      expect(key, matches(RegExp(r'^\d{6}$')));

      await phone.play(await phone.me(), minute: 1);
      await SyncClient(phone.store, host: '127.0.0.1', port: port, key: key).sync();
      expect(await hub.sessions(), hasLength(1));
      await until(() => c.read(syncControllerProvider).hubLastReceived != null);

      // Ausschalten stoppt den Server.
      await c.read(settingsProvider.notifier).update((s) => s.copyWith(syncRole: SyncRole.off));
      c.read(syncControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await expectLater(
        SyncClient(phone.store, host: '127.0.0.1', port: port, key: key, timeout: const Duration(seconds: 1)).sync(),
        throwsA(isA<SyncException>()),
      );
    });

    test('auf dem iPhone wird Hub wie Aus behandelt', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final d = Device();
      addTearDown(d.db.close);
      final c = await containerFor(d, {'sync.role': 'hub'});
      expect(c.read(syncControllerProvider).role, SyncRole.off);
    });
  });
}
