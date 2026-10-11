import 'package:dartlab/core/l10n.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/dart_source/data/autodarts_diagnostics.dart';
import 'package:dartlab/features/dart_source/domain/coordinate_calibration.dart';
import 'package:dartlab/features/dart_source/presentation/diagnostics_dialog.dart';
import 'package:dartlab/features/dart_source/presentation/recording_sheet.dart';
import 'package:dartlab/features/dart_source/data/recording_analysis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/recordings.dart';

/// Liefert feste Ergebnisse statt echter Netzwerkzugriffe.
class FakeDiagnostics extends AutodartsDiagnostics {
  FakeDiagnostics(String host, int port, this.result, this.calls) : super(host: host, port: port);
  final List<DiagnosticCheck> result;
  final List<String> calls;

  @override
  Future<List<DiagnosticCheck>> run() async {
    calls.add('$host:$port');
    return result;
  }
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Optionen').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Verbindungstest nutzt die eingetragene Adresse und zeigt Hinweise', (tester) async {
    final calls = <String>[];
    await pumpApp(tester, prefs: {'settings.sourceKind': 'autodartsLocal'}, overrides: [
      diagnosticsFactoryProvider.overrideWithValue(
        (host, port) => FakeDiagnostics(host, port, const [
          DiagnosticCheck(CheckKind.http, CheckResult.failed, reason: CheckReason.refused),
          DiagnosticCheck(CheckKind.stateFormat, CheckResult.skipped),
        ], calls),
      ),
    ]);
    await openSettings(tester);
    await tester.enterText(find.byKey(const Key('host-field')), '192.168.0.42');
    await tester.scrollUntilVisible(find.byKey(const Key('test-connection')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('test-connection')));
    await tester.pumpAndSettle();

    expect(calls, ['192.168.0.42:3180']);
    expect(find.text('Verbindungstest 192.168.0.42:3180'), findsOneWidget);
    expect(find.byKey(const Key('check-http')), findsOneWidget);
    expect(find.textContaining('Verbindung abgelehnt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('diag-again')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
  });

  testWidgets('Mitschnitt-Auswertung schlägt Kalibrierung vor, Einstellungen zeigen und setzen sie zurück', (tester) async {
    final container = await pumpApp(tester);
    final analysis = RecordingAnalysis.analyze(recording(sample, (p) => BoardPoint(p.x, -p.y)));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RecordingAnalysisView(analysis: analysis)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calibration-suggestion')), findsOneWidget);
    expect(find.text('y gespiegelt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('apply-calibration')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).coordCalibration, const CoordinateCalibration(mirrorY: true));
    expect(find.byKey(const Key('calibration-suggestion')), findsNothing);
    expect(find.text('100,0 %'), findsWidgets);
  });

  testWidgets('Kalibrierung in den Einstellungen zurücksetzen', (tester) async {
    final container = await pumpApp(tester, prefs: {'settings.sourceKind': 'autodartsLocal', 'settings.coordCalibration': const CoordinateCalibration(mirrorY: true).encode()});
    await openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('reset-calibration')));
    await tester.pumpAndSettle();
    expect(find.text('y gespiegelt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset-calibration')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).coordCalibration, CoordinateCalibration.identity);
    expect(find.text('Keine (Standard)'), findsOneWidget);
  });

  testWidgets('Debug: Mitschnitt prüfen ohne Daten meldet das', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('open-debug')), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('open-debug')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-log')));
    await tester.pump();
    expect(find.text('Noch keine Rohdaten aufgezeichnet.'), findsOneWidget);
  });
}
