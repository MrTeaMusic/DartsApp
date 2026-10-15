import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/second_screen/data/screen_client.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/second_screen/presentation/screen_feed.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/darts.dart';
import '../../helpers/fake_live_source.dart';
import '../../helpers/pump_app.dart' show testSourceFactory;

Future<ProviderContainer> container([Map<String, Object> prefs = const {}, DartSourceFactory factory = testSourceFactory]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    appDatabaseProvider.overrideWithValue(db),
    dartSourceFactoryProvider.overrideWithValue(factory),
    botTimingProvider.overrideWithValue(const BotTiming(firstDart: Duration(hours: 1))),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> until(bool Function() done, {Duration max = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Die Test-Bindung ersetzt HttpClient durch eine Attrappe; hier wird über
  // localhost wirklich gesprochen.
  HttpOverrides.global = null;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('Feed: Training und Match erkennen, schwach zuhören, nichts starten', () async {
    final c = await container();
    final feed = c.read(screenFeedProvider);
    expect(feed.snapshot().isIdle, isTrue);

    var changes = 0;
    feed.attach(() => changes++);
    // Zuhören startet keinen Live-Modus (er schreibt sonst mit).
    expect(c.exists(autodartsLiveProvider), isFalse);
    expect(feed.snapshot().isIdle, isTrue);
    expect(c.exists(autodartsLiveProvider), isFalse);

    final game = c.read(activeGameProvider.notifier);
    await game.start(X01Solo.definition, const {'startScore': 301});
    expect(changes, greaterThan(0));
    game.handle(DartThrown(d('T20')));
    final s = feed.snapshot();
    expect(s.kind, ScreenKind.training);
    expect(s.players.single.score, '241');

    // Ohne Viewer hört der Feed nicht mehr zu.
    feed.detach();
    final before = changes;
    game.handle(DartThrown(d('T20')));
    expect(changes, before);
    await game.close();

    // Ein Match hat Vorrang vor allem anderen.
    await c.read(matchControllerProvider.notifier).start(const MatchSetup(
      format: MatchFormat(startScore: 501, legsToWin: 1),
      players: [MatchPlayer.human('Ben'), MatchPlayer.bot('CPU', average: 50)],
    ));
    final m = feed.snapshot();
    expect(m.kind, ScreenKind.match);
    expect(m.players.map((p) => p.name), ['Ben', 'CPU']);
    expect(c.exists(autodartsLiveProvider), isFalse);
  });

  test('Feed: Live-Modus nur, solange der Live-Bildschirm offen ist', () async {
    final live = FakeLiveSource();
    final c = await container({'settings.sourceKind': 'autodartsLocal'}, (kind, host, port) => live);
    final feed = c.read(screenFeedProvider);
    var changes = 0;
    feed.attach(() => changes++);
    expect(feed.snapshot().isIdle, isTrue);

    // Live-Bildschirm öffnen (hält den Provider), Darts kommen an.
    final sub = c.listen(autodartsLiveProvider, (_, _) {});
    live.dart('T20');
    live.dart('S20');
    final s = feed.snapshot();
    expect(s.kind, ScreenKind.live);
    expect(s.visit, ['T20', 'S20']);
    expect(changes, greaterThan(0));

    // Bildschirm zu: der zweite Bildschirm zeigt wieder „Warte auf Spiel“,
    // und Lesen startet das Mitschreiben nicht neu.
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(feed.snapshot().isIdle, isTrue);
    // Die Speichervorgänge des Live-Modus abwarten.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  group('Hub', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('zählt Bildschirme und schickt das laufende Training', () async {
      final free = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = free.port;
      await free.close();
      final c = await container({'sync.role': 'hub', 'sync.port': port});
      c.listen(syncControllerProvider, (_, _) {});
      await until(() => c.read(syncControllerProvider).hubRunning);
      final key = c.read(settingsProvider).syncKey;

      final game = c.read(activeGameProvider.notifier);
      await game.start(X01Solo.definition, const {'startScore': 501});

      final link = await connectScreen(host: '127.0.0.1', port: port, key: key);
      final received = <ScreenState>[];
      link.states.listen(received.add);
      await until(() => received.isNotEmpty);
      expect(received.first.kind, ScreenKind.training);
      expect(received.first.players.single.score, '501');
      await until(() => c.read(syncControllerProvider).screenViewers == 1);

      game.handle(DartThrown(d('T20')));
      game.handle(DartThrown(d('T19')));
      await until(() => received.last.players.single.score == '384');

      await game.close();
      await until(() => received.last.isIdle);

      await link.close();
      await until(() => c.read(syncControllerProvider).screenViewers == 0);
    });
  });
}
