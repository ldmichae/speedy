import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';

final samples = [
  for (var i = 0; i <= 120; i++)
    RideSample(
      t: i.toDouble(),
      target: 200,
      power: 190 + i % 20,
      smoothedPower: 195,
      cadence: 88,
      speed: 36,
    ),
];

void main() {
  group('nearestSample', () {
    final s = [for (final t in [0.0, 10.0, 20.0]) RideSample(t: t)];

    test('picks the closest sample in time', () {
      expect(nearestSample(s, 4)!.t, 0);
      expect(nearestSample(s, 6)!.t, 10);
      expect(nearestSample(s, 14.9)!.t, 10);
      expect(nearestSample(s, 15.1)!.t, 20);
    });

    test('clamps beyond either end and handles no samples', () {
      expect(nearestSample(s, -50)!.t, 0);
      expect(nearestSample(s, 500)!.t, 20);
      expect(nearestSample(const [], 5), isNull);
    });
  });

  group('hoverRows', () {
    const sample = RideSample(
        t: 5, target: 200, power: 203, cadence: 88.6, speed: 36, heartRate: null);

    test('one row per visible metric, with units', () {
      final rows = hoverRows(
          sample, [RideMetric.target, RideMetric.power, RideMetric.cadence],
          UnitSystem.metric);
      expect(rows.map((r) => r.$2), ['200 W', '203 W', '89 rpm']);
      expect(rows.map((r) => r.$1),
          [RideMetric.target, RideMetric.power, RideMetric.cadence]);
    });

    test('missing values show a dash', () {
      final rows = hoverRows(sample, [RideMetric.heartRate], UnitSystem.metric);
      expect(rows.single.$2, '—');
    });

    test('speed follows the ride units', () {
      expect(hoverRows(sample, [RideMetric.speed], UnitSystem.metric).single.$2,
          '36.0 km/h');
      expect(hoverRows(sample, [RideMetric.speed], UnitSystem.imperial).single.$2,
          '22.4 mph');
    });

    test('only the metrics passed in are listed', () {
      expect(hoverRows(sample, const [], UnitSystem.metric), isEmpty);
    });
  });

  group('hovering the chart', () {
    Future<(TestGesture, RenderObject)> pump(WidgetTester tester,
        {ChartSettings settings = const ChartSettings()}) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 600,
            height: 300,
            child: RideChart(samples: samples, settings: settings),
          ),
        ),
      ));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(1, 1));
      addTearDown(gesture.removePointer);
      final render = tester.renderObject(find.descendant(
          of: find.byType(RideChart), matching: find.byType(CustomPaint)));
      return (gesture, render);
    }

    // 5 horizontal grid lines are always drawn; hovering adds the crosshair.
    const gridLines = 5;

    testWidgets('a line and tooltip appear on hover and go away on exit',
        (tester) async {
      final (gesture, render) = await pump(tester);
      expect(render, paintsExactlyCountTimes(#drawLine, gridLines));
      expect(render, paintsExactlyCountTimes(#drawRRect, 0));

      await gesture.moveTo(tester.getCenter(find.byType(RideChart)));
      await tester.pump();
      expect(render, paintsExactlyCountTimes(#drawLine, gridLines + 1));
      expect(render, paintsExactlyCountTimes(#drawRRect, 2)); // tooltip fill + border

      await gesture.moveTo(const Offset(1, 1)); // outside the chart
      await tester.pump();
      expect(render, paintsExactlyCountTimes(#drawLine, gridLines));
      expect(render, paintsExactlyCountTimes(#drawRRect, 0));
    });

    testWidgets('no line over the axis labels outside the plot area',
        (tester) async {
      final (gesture, render) = await pump(tester);
      final box = tester.getRect(find.byType(RideChart));

      await gesture.moveTo(Offset(box.left + 10, box.center.dy)); // y-axis labels
      await tester.pump();

      expect(render, paintsExactlyCountTimes(#drawLine, gridLines));
    });

    testWidgets('the tooltip stays inside the chart near either edge',
        (tester) async {
      final (gesture, _) = await pump(tester,
          settings: ChartSettings(visible: RideMetric.values.toSet()));
      final box = tester.getRect(find.byType(RideChart));

      for (final x in [box.left + 45, box.right - 45]) {
        await gesture.moveTo(Offset(x, box.center.dy));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('hovering with nothing selected or no data does not throw',
        (tester) async {
      final (gesture, _) = await pump(tester, settings: const ChartSettings(visible: {}));
      await gesture.moveTo(tester.getCenter(find.byType(RideChart)));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 600,
            height: 300,
            child: RideChart(samples: const [], settings: const ChartSettings()),
          ),
        ),
      ));
      await gesture.moveTo(tester.getCenter(find.byType(RideChart)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
