import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/daylight.dart';

void main() {
  Daylight at(int hour) => Daylight.at(DateTime(2026, 6, 1, hour));

  test('noon is bright and blue, midnight is dark', () {
    final noon = at(12), midnight = at(0);
    expect(noon.sunHeight, closeTo(1, 1e-9));
    expect(noon.lightIntensity, closeTo(3, 1e-9));
    expect(noon.horizon.b, greaterThan(noon.horizon.r));
    expect(midnight.horizon.length, lessThan(0.1));
    expect(midnight.ambient, lessThan(noon.ambient));
    expect(
        midnight.lightDirection.y, lessThan(0)); // moon still lights the road
  });

  test('dusk glows orange and the sun is low in the west', () {
    final dusk = at(18);
    expect(dusk.horizon.r, greaterThan(dusk.horizon.b));
    expect(dusk.toSun.x, lessThan(-0.8));
    expect(at(6).toSun.x, greaterThan(0.8)); // rises in the east
  });
}
