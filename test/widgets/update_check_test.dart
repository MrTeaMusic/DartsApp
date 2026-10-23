import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/update/presentation/update_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_update.dart';
import '../helpers/pump_app.dart';

void main() {
  Future<void> openSettingsCard(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).go(Routes.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('update-settings-card')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  group('Hinweis auf der Startseite', () {
    testWidgets('zeigt Version und Kurzfassung, „Später“ blendet aus', (tester) async {
      final gh = FakeGitHub();
      final c = await pumpApp(tester, overrides: updateOverrides(github: gh));
      expect(gh.calls, 1);
      final banner = find.byKey(const Key('update-banner'));
      expect(banner, findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('DartLab 0.10.0 · Build 12')), findsOneWidget);
      expect(find.text('Online-Matches: eigene Statistik mit Verlauf (#33)'), findsOneWidget);
      expect(find.text('… und 2 weitere Änderungen'), findsOneWidget);
      // Kein Dialog: die Startseite bleibt bedienbar.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('home-open-games')), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-later')));
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
      expect(c.read(sharedPreferencesProvider).getInt('update.skippedBuild'), 12);
    });

    testWidgets('Herunterladen → gespeichert → Ordner öffnen', (tester) async {
      final gh = FakeGitHub();
      final host = FakeUpdateHost();
      await pumpApp(tester, overrides: updateOverrides(github: gh, host: host, client: FakeUpdateClient(gh)));
      await tester.tap(find.byKey(const Key('update-download')));
      await tester.pumpAndSettle();
      expect(text(tester, 'update-downloaded'), 'Gespeichert in Downloads: DartLab-windows-0.10.0-b12.zip');
      expect(find.textContaining('in deinen DartLab-Ordner kopieren'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-open-folder')));
      await tester.pumpAndSettle();
      expect(host.opened, [host.downloads]);
    });

    testWidgets('Download gescheitert: Nochmal oder Browser', (tester) async {
      final gh = FakeGitHub();
      final host = FakeUpdateHost();
      final client = FakeUpdateClient(gh)..fail = true;
      await pumpApp(tester, overrides: updateOverrides(github: gh, host: host, client: client));
      await tester.tap(find.byKey(const Key('update-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-download-failed')), findsOneWidget);
      await tester.tap(find.text('Im Browser öffnen'));
      await tester.pumpAndSettle();
      expect(host.opened.single, contains('/releases/tag/v0.10.0-b12'));
    });

    testWidgets('iOS: kein Download, Hinweis auf den Mac', (tester) async {
      final gh = FakeGitHub();
      await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: updateOverrides(github: gh, host: FakeUpdateHost(platform: null, isIos: true)),
      );
      expect(find.byKey(const Key('update-banner')), findsOneWidget);
      expect(find.byKey(const Key('update-ios-hint')), findsOneWidget);
      expect(find.byKey(const Key('update-download')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selbst gebaut: sucht nicht, kein Hinweis', (tester) async {
      final dev = FakeGitHub();
      await pumpApp(tester, overrides: updateOverrides(github: dev, build: 0));
      expect(dev.calls, 0);
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });

    testWidgets('offline beim Start: still', (tester) async {
      final gh = FakeGitHub(offlineReply);
      await pumpApp(tester, overrides: updateOverrides(github: gh));
      expect(gh.calls, 1);
      expect(find.byKey(const Key('update-banner')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('GitHub'), findsNothing);
    });
  });

  group('Optionen › Updates', () {
    testWidgets('zeigt die Version und meldet „neueste Version“', (tester) async {
      final gh = FakeGitHub();
      final c = await pumpApp(tester, overrides: updateOverrides(github: gh, build: 12));
      await openSettingsCard(tester, c);
      expect(text(tester, 'update-version'), 'Version 0.10.0 · Build 12');
      expect(text(tester, 'update-status'), 'Du hast die neueste Version.');
      await tester.tap(find.byKey(const Key('update-check')));
      await tester.pumpAndSettle();
      expect(gh.calls, 2);
      expect(text(tester, 'update-status'), 'Du hast die neueste Version.');
    });

    testWidgets('manuelle Suche offline und mit Rate-Limit: freundliche Meldung', (tester) async {
      final gh = FakeGitHub(offlineReply);
      final c = await pumpApp(tester, overrides: updateOverrides(github: gh));
      await openSettingsCard(tester, c);
      expect(text(tester, 'update-status'), 'Sucht beim Start höchstens einmal am Tag von allein.');
      await tester.tap(find.byKey(const Key('update-check')));
      await tester.pumpAndSettle();
      expect(text(tester, 'update-status'), startsWith('Keine Verbindung zu GitHub.'));
      gh.reply = rateLimitReply;
      await tester.tap(find.byKey(const Key('update-check')));
      await tester.pumpAndSettle();
      expect(text(tester, 'update-status'), startsWith('GitHub bremst gerade'));
    });

    testWidgets('neue Version: Herunterladen auch hier', (tester) async {
      final gh = FakeGitHub();
      final c = await pumpApp(tester, size: const Size(390, 844), overrides: updateOverrides(github: gh, client: FakeUpdateClient(gh)));
      await openSettingsCard(tester, c);
      expect(text(tester, 'update-status'), 'Neue Version 0.10.0 · Build 12 verfügbar.');
      final card = find.byKey(const Key('update-settings-card'));
      final download = find.descendant(of: card, matching: find.byKey(const Key('update-download')));
      expect(download, findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('update-later'))), findsNothing);
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(c.read(updateControllerProvider).downloadPhase, DownloadPhase.done);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selbst gebaut: sucht nur auf Knopfdruck und zeigt die neueste Version', (tester) async {
      final gh = FakeGitHub();
      final host = FakeUpdateHost();
      final c = await pumpApp(tester, overrides: updateOverrides(github: gh, build: 0, host: host));
      await openSettingsCard(tester, c);
      expect(gh.calls, 0);
      expect(text(tester, 'update-version'), 'Version 0.10.0 · selbst gebaut');
      expect(text(tester, 'update-status'), 'Selbst gebaut: sucht nur, wenn du hier tippst.');
      await tester.tap(find.byKey(const Key('update-check')));
      await tester.pumpAndSettle();
      expect(gh.calls, 1);
      expect(text(tester, 'update-status'), contains('Neueste auf GitHub: 0.10.0 · Build 12'));
      await tester.tap(find.byKey(const Key('update-release-page')));
      await tester.pumpAndSettle();
      expect(host.opened.single, contains('v0.10.0-b12'));
      // Kein Hinweis auf der Startseite.
      c.read(routerProvider).go(Routes.home);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });
  });
}
