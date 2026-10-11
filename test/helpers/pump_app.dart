import 'package:dartlab/app.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/dart_source/data/manual_source.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quellen ohne Timer, damit Widget-Tests deterministisch bleiben.
DartSource testSourceFactory(DartSourceKind kind, String host, int port) => switch (kind) {
      DartSourceKind.manual => ManualSource(),
      _ => SimulatorSource(takeoutDelay: Duration.zero),
    };

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  Map<String, Object> prefs = const {},
  DartSourceFactory factory = testSourceFactory,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    dartSourceFactoryProvider.overrideWithValue(factory),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DartLabApp()));
  await tester.pumpAndSettle();
  return container;
}
