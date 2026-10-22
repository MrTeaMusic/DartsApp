import 'dart:convert';

import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:dartlab/features/update/presentation/update_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_update.dart';

AppRelease release([String? tag]) => AppRelease.fromJson(jsonDecode(releaseWithApkReply(tag: tag).body))!;

void main() {
  final now = DateTime(2026, 10, 15, 19, 42);

  group('Asset-Auswahl', () {
    test('Android nimmt genau DartLab-Lite-android.apk', () {
      final a = release().assetFor(ReleasePlatform.android)!;
      expect(a.name, 'DartLab-Lite-android.apk');
      expect(a.size, 31457280);
      expect(a.url.toString(), 'https://github.com/MrTeaMusic/DartsApp/releases/download/v0.10.0-b12/DartLab-Lite-android.apk');
    });

    test('Windows und macOS finden weiter ihre Zip, Android keine davon', () {
      final r = release();
      expect(r.assetFor(ReleasePlatform.windows)!.name, 'DartLab-windows.zip');
      expect(r.assetFor(ReleasePlatform.macos)!.name, 'DartLab-macos.zip');
      expect(r.assetFor(ReleasePlatform.android)!.name, isNot(endsWith('.zip')));
    });

    test('ohne APK am Release gibt es für Android nichts', () {
      final plain = AppRelease.fromJson(jsonDecode(releaseReply().body))!;
      expect(plain.assetFor(ReleasePlatform.android), isNull);
    });

    test('andere Dateien mit ähnlichem Namen zählen nicht', () {
      AppRelease withAssets(List<String> names) => AppRelease.fromJson({
            'tag_name': 'v1.0.0-b1',
            'html_url': 'https://github.com/x/y/releases/tag/v1.0.0-b1',
            'assets': [
              for (final n in names) {'name': n, 'browser_download_url': 'https://example.com/$n', 'size': 1},
            ],
          })!;
      expect(withAssets(['DartLab-android.apk', 'DartLab-Lite-android.apk.sha256', 'DartLab-Lite-windows.zip']).assetFor(ReleasePlatform.android),
          isNull);
      expect(withAssets(['dartlab-lite-ANDROID.APK']).assetFor(ReleasePlatform.android)?.name, 'dartlab-lite-ANDROID.APK');
    });

    test('Zwischenspeicher behält die APK', () {
      final back = AppRelease.fromJson(jsonDecode(jsonEncode(release().toJson())))!;
      expect(back.assetFor(ReleasePlatform.android)!.name, 'DartLab-Lite-android.apk');
    });
  });

  test('UpdateHost kennt Android als Plattform, iOS und Linux nicht', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const host = UpdateHost();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(host.platform, ReleasePlatform.android);
    expect(host.isIos, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(host.platform, ReleasePlatform.windows);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(host.platform, isNull);
    expect(host.isIos, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(host.platform, isNull);
  });

  group('Aktion', () {
    Future<ProviderContainer> container(
      FakeGitHub gh, {
      int build = 10,
      FakeUpdateHost? host,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        ...updateOverrides(github: gh, build: build, host: host ?? FakeUpdateHost(platform: ReleasePlatform.android), clock: () => now),
      ]);
      addTearDown(c.dispose);
      c.read(updateControllerProvider);
      await pumpEventQueue();
      return c;
    }

    test('Herunterladen öffnet den Link der APK im Browser, ohne selbst zu laden', () async {
      final gh = FakeGitHub(releaseWithApkReply);
      final host = FakeUpdateHost(platform: ReleasePlatform.android);
      final c = await container(gh, host: host);
      expect(c.read(updateControllerProvider).showBanner, isTrue);
      await c.read(updateControllerProvider.notifier).download();
      expect(host.opened, ['https://github.com/MrTeaMusic/DartsApp/releases/download/v0.10.0-b12/DartLab-Lite-android.apk']);
      final s = c.read(updateControllerProvider);
      expect(s.downloadPhase, DownloadPhase.idle, reason: 'der Browser lädt, nicht die App');
      expect(s.file, isNull);
    });

    test('ohne APK am Release öffnet sich die Release-Seite', () async {
      final gh = FakeGitHub();
      final host = FakeUpdateHost(platform: ReleasePlatform.android);
      final c = await container(gh, host: host);
      await c.read(updateControllerProvider.notifier).download();
      expect(host.opened, ['https://github.com/MrTeaMusic/DartsApp/releases/tag/v0.10.0-b12']);
    });

    test('Build 0 (selbst gebaut) meldet nie ein Update und sucht nicht von allein', () async {
      final gh = FakeGitHub(releaseWithApkReply);
      final c = await container(gh, build: 0);
      expect(gh.calls, 0);
      final s = c.read(updateControllerProvider);
      expect(s.updateAvailable, isFalse);
      expect(s.showBanner, isFalse);
      await c.read(updateControllerProvider.notifier).check();
      final after = c.read(updateControllerProvider);
      expect(after.status, UpdateStatus.devBuild);
      expect(after.updateAvailable, isFalse);
      expect(after.showBanner, isFalse);
    });

    test('gleiche Build-Nummer: kein Update; höchstens eine Suche am Tag', () async {
      final gh = FakeGitHub(releaseWithApkReply);
      final c = await container(gh, build: 12);
      expect(c.read(updateControllerProvider).showBanner, isFalse);
      expect(gh.calls, 1);
      final sp = c.read(sharedPreferencesProvider);
      // Neustart nach 23 Stunden: keine neue Anfrage.
      final saved = {
        'update.lastCheck': now.subtract(const Duration(hours: 23)).millisecondsSinceEpoch,
        'update.latest': sp.getString('update.latest')!,
      };
      final again = FakeGitHub(releaseWithApkReply);
      await container(again, build: 12, prefs: saved);
      expect(again.calls, 0);
    });
  });
}
