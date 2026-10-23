import 'dart:math' as math;

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/live_remote/data/live_packet.dart';
import 'package:dartlab/features/live_remote/presentation/live_push_controller.dart';
import 'package:dartlab/features/live_remote/presentation/live_viewer_controller.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/second_screen/presentation/screen_feed.dart';
import 'package:dartlab/features/live_remote/data/live_pusher.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/darts.dart';
import '../../helpers/fake_cloud.dart';
import '../../helpers/pump_app.dart' show testSourceFactory;

final secret = CloudSecret.generate(math.Random(51));
const url = 'https://dartlab-sync.ben.workers.dev';

Future<void> until(bool Function() done, {Duration max = const Duration(seconds: 8), String? what}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung${what == null ? '' : ': $what'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Bens Gerät (Haupt-App) oder Vaters Handy (Lite) am selben Cloud-Speicher.
Future<ProviderContainer> device(FakeCloud cloud, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues({'sync.cloudUrl': url, 'sync.cloudSecret': secret.text, ...prefs});
  final sp = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    appDatabaseProvider.overrideWithValue(db),
    dartSourceFactoryProvider.overrideWithValue(testSourceFactory),
    cloudHttpClientProvider.overrideWithValue(cloud.client),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('Bens echtes Training und Match kommen verschlüsselt beim Zuschauer an', () async {
    final cloud = FakeCloud();
    // Der Tresor existiert (Ben hat schon einmal abgeglichen).
    cloud.vault((await secret.keys()).token).meta = 'x';

    final ben = await device(cloud, {'sync.role': 'cloud', 'sync.liveShare': true});
    ben.listen(livePushControllerProvider, (_, _) {});
    await until(() => ben.read(livePushControllerProvider).status == LivePushStatus.waiting, what: 'bereit');
    expect(cloud.livePuts, 0, reason: 'ohne Spiel nichts');

    // Vaters Handy schaut zu.
    final dad = await device(cloud, {'sync.role': 'cloud'});
    final seen = <LiveViewState>[];
    dad.listen(liveViewerProvider, (_, n) => seen.add(n), fireImmediately: true);
    LiveViewerController.pollPlaying = const Duration(milliseconds: 50);
    LiveViewerController.pollIdle = const Duration(milliseconds: 100);
    addTearDown(() {
      LiveViewerController.pollPlaying = const Duration(seconds: 2);
      LiveViewerController.pollIdle = const Duration(seconds: 5);
    });
    final viewer = dad.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.last.status == LiveViewStatus.notPlaying);

    // Trainingsspiel: X01 solo.
    final game = ben.read(activeGameProvider.notifier);
    await game.start(X01Solo.definition, const {'startScore': 301});
    await until(() => seen.last.status == LiveViewStatus.playing, what: 'Training beim Zuschauer');
    expect(seen.last.screen!.kind, ScreenKind.training);
    expect(seen.last.screen!.players.single.score, '301');
    game.handle(DartThrown(d('T20')));
    await until(() => seen.last.screen?.players.single.score == '241', what: 'Dart beim Zuschauer');

    // Derselbe Stand wie beim Hub (gleiche Funktion): Ben-seitig und Zuschauer-seitig gleich.
    final keys = await secret.keys();
    final packet = await openLivePacket(keys, cloud.vault(keys.token).live!);
    expect(packet.state.toJson(), ben.read(screenFeedProvider).snapshot().toJson());

    // Spiel zu: idle, der Zuschauer sieht "spielt nicht".
    await game.close();
    await until(() => seen.last.status == LiveViewStatus.notPlaying, what: 'Spielende');

    // Match gegen den Bot.
    await ben.read(matchControllerProvider.notifier).start(const MatchSetup(
      format: MatchFormat(startScore: 501, legsToWin: 1),
      players: [MatchPlayer.human('Ben'), MatchPlayer.bot('CPU', average: 50)],
    ));
    await until(() => seen.last.status == LiveViewStatus.playing && seen.last.screen!.kind == ScreenKind.match, what: 'Match beim Zuschauer');
    expect(seen.last.screen!.players.map((p) => p.name), ['Ben', 'CPU']);

    // Auf dem Server liegt nichts im Klartext.
    expect(cloud.dump(), isNot(contains('CPU')));
    expect(cloud.requests.where((r) => r.startsWith('PUT /v1/live')).length, lessThan(12));

    viewer.setActive(false);
  });
}
