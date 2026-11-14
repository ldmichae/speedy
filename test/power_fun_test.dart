import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/power_fun.dart';
import 'package:indoor_cycling/core/ride_recording.dart';

void main() {
  test('rideJoules is power x time', () {
    final s = [
      for (var t = 0; t <= 10; t++) RideSample(t: t.toDouble(), power: 200),
    ];
    expect(rideJoules(s), 2000);
    expect(rideJoules(const []), 0);
  });

  test('energyText switches to kWh', () {
    expect(energyText(3.6e6 * 0.15), '150 Wh');
    expect(energyText(3.6e6 * 1.5), '1.50 kWh');
  });

  test('a one-hour 150 W ride has a few comparisons', () {
    final f = funFacts(150 * 3600);
    expect(f.length, 4);
    expect(f.first, 'toast 10 slices of bread');
    expect(f[1], 'run a desk fan for 5 hours');
  });

  test('tiny and empty rides still behave', () {
    expect(funFacts(0), isEmpty);
    expect(funFacts(600), ['light an LED bulb for 60 seconds']);
    expect(funFacts(100), ['run a desk fan for 3 seconds']); // fallback
  });
}
