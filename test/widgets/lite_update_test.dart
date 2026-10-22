import 'package:dartlab/features/update/domain/app_release.dart';
import 'package:dartlab/features/update/presentation/update_controller.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_update.dart';
import '../helpers/lite_app.dart';

const apkUrl = 'https://github.com/MrTeaMusic/DartsApp/releases/download/v0.10.0-b12/DartLab-Lite-android.apk';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<({ProviderContainer c, FakeGitHub gh, FakeUpdateHost host})> pump(
    WidgetTester tester, {
    int build = 10,
    GitHubReply reply = releaseWithApkReply,
    Size size = const Size(360, 800),
  }) async {
    final gh = FakeGitHub(reply);
    final host = FakeUpdateHost(platform: ReleasePlatform.android);
    final app = await pumpLiteWithBen(tester, size: size, overrides: updateOverrides(github: gh, build: build, host: host));
    return (c: app.c, gh: gh, host: host);
  }

  testWidgets('Hinweis oben in der Statistik: Schritte, Hinweis zur Erlaubnis, Herunterladen öffnet den Browser', (tester) async {
    final (:c, :gh, :host) = await pump(tester);
    expect(gh.calls, 1);
    final banner = find.byKey(const Key('update-banner'));
    expect(banner, findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('Neue Version verfügbar')), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('DartLab Lite 0.10.0 · Build 12')), findsOneWidget);
    // Die Änderungen der Haupt-App gehören nicht dazu.
    expect(find.descendant(of: banner, matching: find.textContaining('Online-Matches')), findsNothing);
    // Der Hinweis bleibt kurz; die Schritte stehen im Blatt „So geht’s“.
    expect(find.byKey(const Key('update-android-steps')), findsOneWidget);
    expect(find.text('In drei Schritten: herunterladen, Datei öffnen, installieren.'), findsOneWidget);
    expect(find.byKey(const Key('update-android-allow')), findsNothing);
    await tester.tap(find.byKey(const Key('update-android-howto')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('update-android-sheet'));
    expect(sheet, findsOneWidget);
    for (final t in ['Herunterladen:', 'Datei öffnen:', 'Installieren:']) {
      expect(find.descendant(of: sheet, matching: find.textContaining(t, findRichText: true)), findsOneWidget, reason: t);
    }
    for (final n in ['1.', '2.', '3.']) {
      expect(find.descendant(of: sheet, matching: find.text(n)), findsOneWidget);
    }
    expect(find.textContaining('Die alte Version wird ersetzt, deine Daten bleiben erhalten', findRichText: true), findsOneWidget);
    expect(find.textContaining('fragt Android, ob der Browser Apps installieren darf'), findsOneWidget);
    expect(find.textContaining('Erlaube das einmalig'), findsOneWidget);
    // Kein Zip-Hinweis, keine Windows- oder macOS-Anleitung.
    expect(find.byKey(const Key('update-open-folder')), findsNothing);
    expect(find.textContaining('entpacken'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await tester.tap(find.byKey(const Key('update-download')));
    await tester.pumpAndSettle();
    expect(host.opened, [apkUrl]);
    expect(c.read(updateControllerProvider).downloadPhase, DownloadPhase.idle);
    expect(banner, findsOneWidget, reason: 'der Hinweis bleibt, bis die neue Version installiert ist');
    await shutdownApp(tester, c);
  });

  testWidgets('„Später“ blendet den Hinweis aus, in den Optionen bleibt die Anleitung', (tester) async {
    final (:c, :gh, :host) = await pump(tester);
    await tester.tap(find.byKey(const Key('update-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-banner')), findsNothing);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('update-settings-card'));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find.descendant(of: find.byKey(const Key('lite-settings')), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('update-version'))).data, 'Version 0.10.0 · Build 10');
    expect(find.text('Neue Version 0.10.0 · Build 12 verfügbar.'), findsOneWidget);
    expect(find.byKey(const Key('update-android-steps')), findsOneWidget);
    expect(find.byKey(const Key('update-android-allow')), findsOneWidget, reason: 'in der Karte stehen die Schritte gleich da');
    expect(find.textContaining('Herunterladen:', findRichText: true), findsOneWidget);
    // Ohne „Später“ in der Karte.
    expect(find.descendant(of: card, matching: find.byKey(const Key('update-later'))), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('update-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('update-download')));
    await tester.pumpAndSettle();
    expect(host.opened, [apkUrl]);
    await shutdownApp(tester, c);
  });

  testWidgets('„Nach Updates suchen“ in den Optionen', (tester) async {
    final (:c, :gh, :host) = await pump(tester, build: 12);
    expect(find.byKey(const Key('update-banner')), findsNothing, reason: 'gleiche Version');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
    await tester.pumpAndSettle();
    final check = find.byKey(const Key('update-check'));
    await tester.scrollUntilVisible(
      check,
      300,
      scrollable: find.descendant(of: find.byKey(const Key('lite-settings')), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    gh.reply = () => releaseWithApkReply(tag: 'v0.10.1-b20');
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(gh.calls, 2);
    expect(find.text('Neue Version 0.10.1 · Build 20 verfügbar.'), findsOneWidget);
    expect(find.byKey(const Key('update-android-steps')), findsOneWidget);
    await shutdownApp(tester, c);
  });

  testWidgets('selbst gebaut (Build 0): kein Hinweis, keine automatische Suche', (tester) async {
    final (:c, :gh, :host) = await pump(tester, build: 0);
    expect(gh.calls, 0);
    expect(find.byKey(const Key('update-banner')), findsNothing);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
    await tester.pumpAndSettle();
    final check = find.byKey(const Key('update-check'));
    await tester.scrollUntilVisible(
      check,
      300,
      scrollable: find.descendant(of: find.byKey(const Key('lite-settings')), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('selbst gebaut', findRichText: true), findsWidgets);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(gh.calls, 1);
    expect(find.byKey(const Key('update-android-steps')), findsNothing, reason: 'Build 0 meldet nie ein Update');
    expect(find.byKey(const Key('update-banner')), findsNothing);
    await shutdownApp(tester, c);
  });

  testWidgets('Release ohne APK: nur der Weg zur Release-Seite', (tester) async {
    final (:c, :gh, :host) = await pump(tester, reply: releaseReply);
    expect(find.byKey(const Key('update-banner')), findsOneWidget);
    expect(find.byKey(const Key('update-android-steps')), findsNothing);
    await tester.tap(find.byKey(const Key('update-download')));
    await tester.pumpAndSettle();
    expect(host.opened.single, contains('/releases/tag/v0.10.0-b12'));
    await shutdownApp(tester, c);
  });
}
