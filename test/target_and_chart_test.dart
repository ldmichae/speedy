import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/target_status.dart';
import 'package:indoor_cycling/ui/dashboard_tiles.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';

void main() {
  group('target status', () {
    test('within 5 W of a small target is on target', () {
      expect(targetStatus(100, 100), TargetStatus.onTarget);
      expect(targetStatus(105, 100), TargetStatus.onTarget);
      expect(targetStatus(95, 100), TargetStatus.onTarget);
      expect(targetStatus(105.4, 100), TargetStatus.above);
      expect(targetStatus(94.6, 100), TargetStatus.below);
    });

    test('a big target allows 3%, so 300 W is not held to 5 W', () {
      expect(targetTolerance(100), 5);
      expect(targetTolerance(300), 9);
      expect(targetStatus(308, 300), TargetStatus.onTarget);
      expect(targetStatus(310, 300), TargetStatus.above);
      expect(targetStatus(290, 300), TargetStatus.below);
    });

    test('delta is rounded watts, signed', () {
      expect(targetDelta(108.4, 100), 8);
      expect(targetDelta(87.6, 100), -12);
      expect(targetDelta(100, 100), 0);
    });

    test('a zero target still has a sane tolerance', () {
      expect(targetStatus(3, 0), TargetStatus.onTarget);
      expect(targetStatus(40, 0), TargetStatus.above);
    });
  });

  group('TargetChip', () {
    Future<void> pump(WidgetTester tester, double power, int target) =>
        tester.pumpWidget(MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1FB5A0), brightness: Brightness.dark),
          ),
          home: Scaffold(body: Center(child: TargetChip(power: power, target: target))),
        ));

    testWidgets('on target says so with a check', (tester) async {
      await pump(tester, 102, 100);
      expect(find.text('On target'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.bySemanticsLabel('On target'), findsOneWidget);
    });

    testWidgets('above target shows a signed delta and an up arrow',
        (tester) async {
      await pump(tester, 118, 100);
      expect(find.text('+18 W'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.bySemanticsLabel('18 watts above target'), findsOneWidget);
    });

    testWidgets('below target shows a signed delta and a down arrow',
        (tester) async {
      await pump(tester, 88, 100);
      expect(find.text('−12 W'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.bySemanticsLabel('12 watts below target'), findsOneWidget);
    });

    testWidgets('the state never depends on colour alone', (tester) async {
      // Each state has its own icon and its own text, besides its colour.
      final seen = <(IconData, String)>{};
      for (final (p, t) in [(100.0, 100), (130.0, 100), (70.0, 100)]) {
        await pump(tester, p, t);
        final icon = tester.widget<Icon>(find.byType(Icon)).icon!;
        final text = tester.widget<Text>(find.descendant(
            of: find.byType(TargetChip), matching: find.byType(Text))).data!;
        seen.add((icon, text));
      }
      expect(seen, hasLength(3));
    });

    testWidgets('off-target text is readable on its container (at least 4.5:1)',
        (tester) async {
      double lum(Color c) => c.computeLuminance();
      double ratio(Color a, Color b) {
        final l1 = lum(a), l2 = lum(b);
        return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
      }

      await pump(tester, 130, 100);
      final box = tester.widget<DecoratedBox>(find.descendant(
          of: find.byType(TargetChip), matching: find.byType(DecoratedBox)));
      final bg = (box.decoration as BoxDecoration).color!;
      final fg = tester.widget<Text>(find.text('+30 W')).style!.color!;
      expect(ratio(bg, fg), greaterThanOrEqualTo(4.5));

      await pump(tester, 100, 100);
      final ok = tester.widget<DecoratedBox>(find.descendant(
          of: find.byType(TargetChip), matching: find.byType(DecoratedBox)));
      final okBg = (ok.decoration as BoxDecoration).color!;
      final okFg = tester.widget<Text>(find.text('On target')).style!.color!;
      expect(ratio(okBg, okFg), greaterThanOrEqualTo(4.5));
    });
  });

  group('smoothSeries', () {
    List<RideSample> at(List<double> ts) => [for (final t in ts) RideSample(t: t)];

    test('0 seconds leaves the values alone', () {
      final s = at([0, 1, 2]);
      final v = <double?>[1, 9, 1];
      expect(smoothSeries(s, v, 0), same(v));
    });

    test('averages over a centred window', () {
      final s = at([0, 1, 2, 3, 4]);
      final v = <double?>[0, 0, 10, 0, 0];
      final out = smoothSeries(s, v, 2); // +-1 s
      expect(out[2], closeTo(10 / 3, 1e-9)); // 0, 10, 0
      expect(out[1], closeTo(10 / 3, 1e-9)); // 0, 0, 10
      expect(out[0], 0);
    });

    test('a steady series stays put, and noise is flattened', () {
      final s = at([for (var i = 0; i < 30; i++) i.toDouble()]);
      final steady = <double?>[for (var i = 0; i < 30; i++) 90];
      expect(smoothSeries(s, steady, 5).every((x) => x == 90), isTrue);

      final noisy = <double?>[for (var i = 0; i < 30; i++) i.isEven ? 84 : 96];
      final out = smoothSeries(s, noisy, 5).whereType<double>().toList();
      final range = out.reduce((a, b) => a > b ? a : b) - out.reduce((a, b) => a < b ? a : b);
      expect(range, lessThan(12 / 2)); // far tighter than the raw 84..96 swing
    });

    test('gaps stay gaps and do not pull values toward zero', () {
      final s = at([0, 1, 2, 3, 4]);
      final v = <double?>[100, null, 100, null, 100];
      final out = smoothSeries(s, v, 4);
      expect(out[1], isNull);
      expect(out[3], isNull);
      expect(out[0], 100);
      expect(out[2], 100);
      expect(out[4], 100);
    });

    test('works at the ends and with a single sample', () {
      expect(smoothSeries(at([0]), [7], 5), [7]);
      expect(smoothSeries(const [], const [], 5), isEmpty);
    });

    test('uses time, not index, so uneven sampling is handled', () {
      final s = at([0, 1, 10, 11]);
      final out = smoothSeries(s, [0, 10, 100, 110], 4);
      expect(out[0], 5); // only 0 and 1 are within 2 s
      expect(out[2], 105); // only 10 and 11
    });
  });

  group('RideMetric smoothing', () {
    test('only the jittery series are smoothed', () {
      expect(RideMetric.cadence.smoothSeconds, greaterThan(0));
      expect(RideMetric.speed.smoothSeconds, greaterThan(0));
      for (final m in [
        RideMetric.target,
        RideMetric.power,
        RideMetric.smoothedPower,
        RideMetric.heartRate
      ]) {
        expect(m.smoothSeconds, 0, reason: m.label);
      }
    });
  });
}
