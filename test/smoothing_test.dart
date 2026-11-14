import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/smoothing.dart';

void main() {
  test('averages samples inside the window and drops old ones', () {
    final s = PowerSmoother(); // 3 s
    expect(s.add(100, const Duration(seconds: 0)), 100);
    expect(s.add(200, const Duration(seconds: 1)), 150);
    expect(s.add(300, const Duration(seconds: 2)), 200);
    // t=4: the t=0 sample is 4 s old and drops; t=1 is exactly 3 s old and stays.
    expect(s.add(400, const Duration(seconds: 4)), 300);
  });

  test('reset clears history', () {
    final s = PowerSmoother();
    s.add(500, Duration.zero);
    s.reset();
    expect(s.add(100, const Duration(seconds: 1)), 100);
  });
}
