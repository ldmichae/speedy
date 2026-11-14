import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_export.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('stored preferences are applied after load', () async {
    SharedPreferences.setMockInitialValues({
      'rideFormat': 'csv',
      'chartMetrics': ['speed', 'heartRate'],
      'chartWindowSeconds': 300,
    });
    final c = container();
    expect(c.read(rideFormatProvider), RideFormat.fit); // default until loaded
    c.read(chartSettingsProvider);
    await settle();

    expect(c.read(rideFormatProvider), RideFormat.csv);
    final s = c.read(chartSettingsProvider);
    expect(s.visible, {RideMetric.speed, RideMetric.heartRate});
    expect(s.window, const Duration(minutes: 5));
  });

  test('a change made before the load finishes is not overwritten', () async {
    SharedPreferences.setMockInitialValues({'rideFormat': 'csv'});
    final c = container();
    c.read(rideFormatProvider);
    c.read(rideFormatProvider.notifier).set(RideFormat.fit); // before load
    await settle();

    expect(c.read(rideFormatProvider), RideFormat.fit);
    expect((await SharedPreferences.getInstance()).getString('rideFormat'), 'fit');
  });

  test('changes are persisted, including hiding every metric', () async {
    SharedPreferences.setMockInitialValues({});
    final c = container();
    c.read(chartSettingsProvider);
    await settle();
    final n = c.read(chartSettingsProvider.notifier);
    for (final m in [...c.read(chartSettingsProvider).visible]) {
      n.toggle(m);
    }
    n.setWindow(const Duration(minutes: 10));
    await settle();

    final p = await SharedPreferences.getInstance();
    expect(p.getStringList('chartMetrics'), isEmpty);
    expect(p.getInt('chartWindowSeconds'), 600);

    final again = container();
    again.read(chartSettingsProvider);
    await settle();
    expect(again.read(chartSettingsProvider).visible, isEmpty);
  });

  test('unknown stored values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({'rideFormat': 'gpx'});
    final c = container();
    c.read(rideFormatProvider);
    await settle();
    expect(c.read(rideFormatProvider), RideFormat.fit);
  });
}
