import 'package:dartlab/core/design/app_theme.dart';
import 'package:dartlab/features/stats/presentation/stats_charts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(List<double> values) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: VolumeChart(labels: [for (var i = 0; i < values.length; i++) '$i'], values: values),
          ),
        ),
      );

  Duration duration(WidgetTester tester) => tester.widget<BarChart>(find.byType(BarChart)).duration;

  testWidgets('Diagramm animiert nur bei neuen Werten, nicht bei jedem Neuaufbau', (tester) async {
    await tester.pumpWidget(host([1, 2, 3]));
    // Neue Werte (z. B. anderer Zeitraum): Animation wie bisher.
    await tester.pumpWidget(host([3, 2, 1]));
    expect(duration(tester), const Duration(milliseconds: 150));
    // Neuaufbau mit denselben Werten während der Animation: unverändert.
    await tester.pumpWidget(host([3, 2, 1]));
    expect(duration(tester), const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    // Später ein Neuaufbau mit denselben Werten: keine Animation.
    await tester.pumpWidget(host([3, 2, 1]));
    expect(duration(tester), Duration.zero);
    // Und wieder neue Werte: Animation.
    await tester.pumpWidget(host([3, 2, 5]));
    expect(duration(tester), const Duration(milliseconds: 150));
  });

  testWidgets('Liniendiagramm: Neuaufbau mit denselben Werten ohne Animation', (tester) async {
    Widget line(List<double> values) => MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: SizedBox(width: 400, height: 200, child: VisitValuesChart(values: values, line: true, average: 40))),
        );
    LineChart chart() => tester.widget<LineChart>(find.byType(LineChart));
    await tester.pumpWidget(line([60, 45, 100]));
    await tester.pumpWidget(line([60, 45, 81]));
    expect(chart().duration, const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpWidget(line([60, 45, 81]));
    expect(chart().duration, Duration.zero);
  });
}
