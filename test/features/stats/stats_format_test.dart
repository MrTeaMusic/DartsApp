import 'package:dartlab/features/stats/presentation/stats_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Veränderung zum Vorzeitraum: Text und Richtung', () {
    final avg = MetricDelta.of(54.3, 52.0, ValueKind.decimal)!;
    expect(avg.text, '+2,3');
    expect(avg.improved, isTrue);

    final rate = MetricDelta.of(0.25, 0.30, ValueKind.percent)!;
    expect(rate.text, '−5,0 Pp');
    expect(rate.improved, isFalse);

    // Bei der Streuung ist weniger besser.
    final spread = MetricDelta.of(30, 35, ValueKind.decimal, higherIsBetter: false)!;
    expect(spread.improved, isTrue);

    final same = MetricDelta.of(10, 10, ValueKind.count)!;
    expect(same.flat, isTrue);
    expect(same.improved, isFalse);
    expect(same.text, '±0');

    expect(MetricDelta.of(1, null, ValueKind.count), isNull);
    expect(MetricDelta.of(90, 30, ValueKind.minutes)!.text, '+1 h');
  });

  test('Dauer und Kennzahlen formatieren', () {
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(80), '1 h 20 min');
    expect(formatMinutes(1400), '23 h');
    expect(formatMetricKey('checkout', 'checkoutRate', 0.4), '40,0 %');
    expect(formatMetricKey('around_the_clock', 'darts', 33), '33');
    expect(formatMetricKey('x01', 'average', 61.234), '61,2');
    expect(formatMetricKey('x01', 'first9', 70.5), '70,5');
  });
}
