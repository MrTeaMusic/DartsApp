import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/app_version.dart';
import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) => File('test/fixtures/update/$name').readAsStringSync();

void main() {
  group('AppBuild', () {
    test('liest Tags des Release-Workflows', () {
      expect(AppBuild.tryParse('v0.10.0-b12'), const AppBuild('0.10.0', 12));
      expect(AppBuild.tryParse('v0.10.0+123'), const AppBuild('0.10.0', 123));
      expect(AppBuild.tryParse('0.11.2'), const AppBuild('0.11.2', 0));
      expect(AppBuild.tryParse(' v1.2.3-b7 '), const AppBuild('1.2.3', 7));
    });

    test('lehnt fremde Tags ab', () {
      for (final t in [null, '', 'latest', 'v1.2', 'release-12', 'v1.2.3-beta', 'v1.2.3-b']) {
        expect(AppBuild.tryParse(t), isNull, reason: '$t');
      }
    });

    test('Build-Nummer entscheidet, wenn beide eine haben', () {
      const running = AppBuild('0.10.0', 12);
      expect(const AppBuild('0.10.0', 13).isNewerThan(running), isTrue);
      expect(const AppBuild('0.10.0', 12).isNewerThan(running), isFalse);
      expect(const AppBuild('0.10.0', 11).isNewerThan(running), isFalse);
      // Version erhöht, Build-Nummer läuft einfach weiter.
      expect(const AppBuild('0.11.0', 14).isNewerThan(running), isTrue);
      // Build-Nummer zählt auch, wenn die Version (versehentlich) kleiner ist.
      expect(const AppBuild('0.9.0', 20).isNewerThan(running), isTrue);
    });

    test('ohne Build-Nummer zählt die Version, numerisch statt alphabetisch', () {
      const dev = AppBuild('0.10.0', 0);
      expect(dev.isDevBuild, isTrue);
      expect(const AppBuild('0.10.0', 5).isNewerThan(dev), isTrue);
      expect(const AppBuild('0.9.9', 50).isNewerThan(dev), isFalse);
      expect(const AppBuild('0.10.1', 1).isNewerThan(dev), isTrue);
      expect(const AppBuild('0.10.0', 0).compareVersion(const AppBuild('0.9.0', 0)), greaterThan(0));
      expect(const AppBuild('1.0.0', 0).compareVersion(const AppBuild('0.99.99', 0)), greaterThan(0));
    });
  });

  group('AppRelease.fromJson', () {
    test('liest die Antwort von /releases/latest', () {
      final r = AppRelease.fromJson(jsonDecode(fixture('latest_release.json')))!;
      expect(r.tag, 'v0.10.0-b12');
      expect(r.build, const AppBuild('0.10.0', 12));
      expect(r.title, 'DartLab 0.10.0 (Build 12)');
      expect(r.pageUrl.toString(), 'https://github.com/MrTeaMusic/DartsApp/releases/tag/v0.10.0-b12');
      expect(r.publishedAt, DateTime.utc(2026, 10, 15, 17, 9, 48));
      expect(r.assets, hasLength(2));
      expect(r.notes, isNot(contains('\r')));

      final win = r.assetFor(ReleasePlatform.windows)!;
      expect(win.name, 'DartLab-windows.zip');
      expect(win.size, 23544107);
      expect(win.url.toString(), endsWith('/v0.10.0-b12/DartLab-windows.zip'));
      expect(r.assetFor(ReleasePlatform.macos)!.name, 'DartLab-macos.zip');
    });

    test('Kurzfassung: drei Punkte ohne Markdown, Installationshinweis weg', () {
      final r = AppRelease.fromJson(jsonDecode(fixture('latest_release.json')))!;
      expect(r.shortNotes(), [
        'Online-Matches: eigene Statistik mit Verlauf (#33)',
        'Zweiter Bildschirm für das Scoreboard (#34)',
        'Checkout-Quiz als neues Trainingsspiel (#35)',
      ]);
      expect(r.hiddenNoteCount(), 2);
      expect(r.shortNotes(max: 10).last, 'Fehler beim Import alter Sicherungen behoben');
    });

    test('übersteht fehlende oder kaputte Felder', () {
      expect(AppRelease.fromJson(null), isNull);
      expect(AppRelease.fromJson('kein Objekt'), isNull);
      expect(AppRelease.fromJson({'tag_name': 'v1.0.0-b1'}), isNull, reason: 'ohne html_url');
      expect(AppRelease.fromJson({'tag_name': 'nightly', 'html_url': 'https://x.y'}), isNull);
      expect(
        AppRelease.fromJson({'tag_name': 'v1.0.0-b1', 'html_url': 'https://x.y', 'draft': true}),
        isNull,
      );
      final r = AppRelease.fromJson({
        'tag_name': 'v1.0.0-b1',
        'html_url': 'https://x.y',
        'name': '',
        'body': null,
        'assets': [
          {'name': 'DartLab-windows.zip'},
          'kaputt',
          {'name': 'DartLab-windows.zip.sha256', 'browser_download_url': 'https://x.y/a'},
        ],
      })!;
      expect(r.title, 'v1.0.0-b1');
      expect(r.notes, '');
      expect(r.shortNotes(), isEmpty);
      expect(r.assetFor(ReleasePlatform.windows), isNull);
    });

    test('Zwischenspeicher: toJson und zurück', () {
      final r = AppRelease.fromJson(jsonDecode(fixture('latest_release.json')))!;
      final back = AppRelease.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.build, r.build);
      expect(back.notes, r.notes);
      expect(back.assetFor(ReleasePlatform.windows)!.url, r.assetFor(ReleasePlatform.windows)!.url);
      expect(back.publishedAt, r.publishedAt);
    });
  });

  test('appVersion passt zur Version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec)!;
    expect(appVersion, m.group(1));
    // Ohne --dart-define gelten Tests als selbst gebaut.
    expect(appVersionName, appVersion);
    expect(appBuildNumber, 0);
  });
}
