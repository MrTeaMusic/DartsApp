import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/update/data/update_client.dart';
import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:dartlab/features/update/presentation/update_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_update.dart';

void main() {
  final now = DateTime(2026, 10, 15, 19, 42);

  Future<ProviderContainer> container(
    FakeGitHub github, {
    int build = 10,
    Map<String, Object> prefs = const {},
    FakeUpdateHost? host,
    FakeUpdateClient? client,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      ...updateOverrides(github: github, build: build, host: host, client: client, clock: () => now),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Startet den Controller und wartet die automatische Suche ab.
  Future<UpdateState> start(ProviderContainer c) async {
    c.read(updateControllerProvider);
    await pumpEventQueue();
    return c.read(updateControllerProvider);
  }

  test('sucht beim Start und meldet die neuere Version', () async {
    final gh = FakeGitHub();
    final c = await container(gh);
    final s = await start(c);
    expect(gh.calls, 1);
    expect(s.status, UpdateStatus.available);
    expect(s.latest!.build, const AppBuild('0.10.0', 12));
    expect(s.showBanner, isTrue);
    final sp = c.read(sharedPreferencesProvider);
    expect(sp.getInt('update.lastCheck'), now.millisecondsSinceEpoch);
    expect(sp.getString('update.latest'), contains('v0.10.0-b12'));
  });

  test('höchstens einmal in 24 Stunden; Treffer bleibt bis dahin gespeichert', () async {
    final first = FakeGitHub();
    final c1 = await container(first);
    await start(c1);
    final sp = c1.read(sharedPreferencesProvider);
    final saved = {
      'update.lastCheck': sp.getInt('update.lastCheck')!,
      'update.latest': sp.getString('update.latest')!,
    };

    // Neustart 23 Stunden später: keine Anfrage, Hinweis kommt aus dem Speicher.
    final again = FakeGitHub();
    final c2 = await container(again, prefs: {
      ...saved,
      'update.lastCheck': now.subtract(const Duration(hours: 23)).millisecondsSinceEpoch,
    });
    final s2 = await start(c2);
    expect(again.calls, 0);
    expect(s2.showBanner, isTrue);

    // 25 Stunden: wieder eine Anfrage.
    final later = FakeGitHub();
    final c3 = await container(later, prefs: {
      ...saved,
      'update.lastCheck': now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
    });
    await start(c3);
    expect(later.calls, 1);
  });

  test('gleiche oder ältere Version: kein Hinweis', () async {
    final gh = FakeGitHub();
    final s = await start(await container(gh, build: 12));
    expect(s.status, UpdateStatus.upToDate);
    expect(s.showBanner, isFalse);
    final newer = await start(await container(FakeGitHub(), build: 30));
    expect(newer.status, UpdateStatus.upToDate);
  });

  test('selbst gebaut: sucht nie von allein, manuell schon, ohne Hinweis', () async {
    final gh = FakeGitHub();
    final c = await container(gh, build: 0);
    final s = await start(c);
    expect(gh.calls, 0);
    expect(s.status, UpdateStatus.idle);
    await c.read(updateControllerProvider.notifier).check();
    final after = c.read(updateControllerProvider);
    expect(gh.calls, 1);
    expect(after.status, UpdateStatus.devBuild);
    expect(after.latest, isNotNull);
    expect(after.showBanner, isFalse);
  });

  test('automatische Suche scheitert still, manuelle zeigt den Grund', () async {
    final gh = FakeGitHub(offlineReply);
    final c = await container(gh);
    final s = await start(c);
    expect(gh.calls, 1);
    expect(s.status, UpdateStatus.idle);
    expect(s.failure, isNull);
    // Kein erfolgreicher Versuch: beim nächsten Start wird erneut gesucht.
    expect(c.read(sharedPreferencesProvider).getInt('update.lastCheck'), isNull);

    await c.read(updateControllerProvider.notifier).check();
    expect(c.read(updateControllerProvider).status, UpdateStatus.failed);
    expect(c.read(updateControllerProvider).failure, UpdateFailure.offline);

    gh.reply = rateLimitReply;
    await c.read(updateControllerProvider.notifier).check();
    expect(c.read(updateControllerProvider).failure, UpdateFailure.rateLimited);

    gh.reply = releaseReply;
    await c.read(updateControllerProvider.notifier).check();
    expect(c.read(updateControllerProvider).status, UpdateStatus.available);
    expect(c.read(updateControllerProvider).failure, isNull);
  });

  test('„Später“ blendet bis zur nächsten Version aus', () async {
    final gh = FakeGitHub();
    final c = await container(gh);
    await start(c);
    await c.read(updateControllerProvider.notifier).later();
    expect(c.read(updateControllerProvider).showBanner, isFalse);
    expect(c.read(sharedPreferencesProvider).getInt('update.skippedBuild'), 12);

    // Nach Neustart bleibt es weg …
    final c2 = await container(FakeGitHub(), prefs: {'update.skippedBuild': 12});
    expect((await start(c2)).showBanner, isFalse);
    // … bis Build 13 erscheint.
    final next = FakeGitHub(() => releaseReply(tag: 'v0.10.0-b13'));
    final c3 = await container(next, prefs: {'update.skippedBuild': 12});
    expect((await start(c3)).showBanner, isTrue);
  });

  test('Download in den Download-Ordner, danach Ordner öffnen', () async {
    final gh = FakeGitHub();
    final host = FakeUpdateHost();
    final client = FakeUpdateClient(gh);
    final c = await container(gh, host: host, client: client);
    await start(c);
    final ctrl = c.read(updateControllerProvider.notifier);
    await ctrl.download();
    final s = c.read(updateControllerProvider);
    expect(s.downloadPhase, DownloadPhase.done);
    expect(s.file!.path, endsWith('DartLab-windows-0.10.0-b12.zip'));
    expect(s.file!.path, startsWith(host.downloads));
    await ctrl.openDownloadFolder();
    expect(host.opened, [host.downloads]);

    client.fail = true;
    await ctrl.download();
    expect(c.read(updateControllerProvider).downloadPhase, DownloadPhase.failed);
  });

  test('macOS lädt die macOS-Zip; ohne passende Datei öffnet sich die Release-Seite', () async {
    final gh = FakeGitHub();
    final mac = FakeUpdateHost(platform: ReleasePlatform.macos);
    final c = await container(gh, host: mac, client: FakeUpdateClient(gh));
    await start(c);
    await c.read(updateControllerProvider.notifier).download();
    expect(c.read(updateControllerProvider).file!.path, endsWith('DartLab-macos-0.10.0-b12.zip'));

    final linux = FakeUpdateHost(platform: null);
    final client = FakeUpdateClient(gh);
    final c2 = await container(gh, host: linux, client: client);
    await start(c2);
    await c2.read(updateControllerProvider.notifier).download();
    expect(client.downloads, 0);
    expect(linux.opened.single, 'https://github.com/MrTeaMusic/DartsApp/releases/tag/v0.10.0-b12');
  });
}
