import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';

void main() {
  test('speed and distance convert to miles', () {
    expect(speedIn(100, UnitSystem.imperial), closeTo(62.137, 0.001));
    expect(speedIn(100, UnitSystem.metric), 100);
    expect(distanceIn(42.195, UnitSystem.imperial), closeTo(26.219, 0.001));
    expect(speedUnit(UnitSystem.imperial), 'mph');
    expect(distanceUnit(UnitSystem.imperial), 'mi');
    expect(speedUnit(UnitSystem.metric), 'km/h');
    expect(distanceUnit(UnitSystem.metric), 'km');
  });

  test('weight converts both ways', () {
    expect(kgToPounds(72.5), closeTo(159.83, 0.01));
    expect(poundsToKg(200), closeTo(90.718, 0.001));
    expect(poundsToKg(kgToPounds(80)), closeTo(80, 1e-9));
  });

  test('height converts to feet and inches and back', () {
    expect(cmToFeetInches(180), (5, 11));
    expect(cmToFeetInches(170), (5, 7));
    expect(cmToFeetInches(152), (5, 0)); // 59.8 in rounds up to 60
    expect(feetInchesToCm(5, 11), 180);
    expect(feetInchesToCm(6, 0), 183);
    expect(feetInchesToCm(5, 10.5), 179);
    // A stored height survives a round trip through feet and inches.
    for (final cm in [150, 165, 172, 180, 193]) {
      final (ft, inch) = cmToFeetInches(cm);
      expect((feetInchesToCm(ft, inch) - cm).abs(), lessThanOrEqualTo(1));
    }
  });

  test('only the speed series changes with ride units', () {
    const s = RideSample(t: 0, power: 200, speed: 36, cadence: 90);

    expect(RideMetric.speed.valueOf(s), 36);
    expect(RideMetric.speed.valueOf(s, UnitSystem.imperial), closeTo(22.37, 0.01));
    expect(RideMetric.speed.unitIn(UnitSystem.imperial), 'mph');
    expect(RideMetric.speed.unitIn(UnitSystem.metric), 'km/h');

    expect(RideMetric.power.valueOf(s, UnitSystem.imperial), 200);
    expect(RideMetric.cadence.valueOf(s, UnitSystem.imperial), 90);
    expect(RideMetric.power.unitIn(UnitSystem.imperial), 'W');
    expect(RideMetric.speed.valueOf(const RideSample(t: 0), UnitSystem.imperial), isNull);
  });
}
