import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/course.dart';
import 'package:indoor_cycling/core/world_path.dart';

void main() {
  // A flat kilometre, then 6 km at 6%, then flat: due east along the equator.
  final drag = WorldPath.of(courseById('long-drag-v1')!.route);

  test('lays the course out in metres east, up and north of the start', () {
    expect(drag.length, closeTo(7500, 1));
    expect(drag.at(0).length, closeTo(0, 1e-6));
    final top = drag.at(7000);
    expect(top.x, closeTo(7000, 5));
    expect(top.y, closeTo(360, 2));
    expect(top.z, closeTo(0, 1e-6));
    // Clamped to the ends.
    expect(drag.at(-50).x, closeTo(0, 1e-6));
    expect(drag.at(99999).x, closeTo(drag.length, 5));
  });

  test('heading east has south on your right', () {
    final h = drag.heading(3000);
    expect(h.x, closeTo(1, 1e-6));
    expect(h.y, 0);
    final r = WorldPath.rightOf(h);
    expect(r.z, closeTo(-1, 1e-6));
  });

  test('ground sits just under the road and rises away from it', () {
    final road = drag.near(3000, 0, 500);
    final p = drag.at(3000);
    final on = groundAt(p.x, p.z, road);
    expect(on.road, lessThanOrEqualTo(drag.step / 2)); // nearest sample
    expect(on.y, closeTo(drag.at(3000).y - roadDepth, 0.5));
    final far = groundAt(p.x, 400, road);
    expect(far.road, closeTo(400, 1));
    expect(far.y, greaterThanOrEqualTo(on.y - 1));
    expect(groundAt(0, 0, const []).y, -roadDepth);
  });

  test('trees are the same each build and keep off the road', () {
    final road = drag.near(3000, 0, 500);
    final a = treesAround(3000, 0, 300, road);
    final b = treesAround(3000, 0, 300, road);
    expect(a, isNotEmpty);
    expect(a, b);
    for (final t in a) {
      expect(groundAt(t.x, t.z, road).road, greaterThanOrEqualTo(12));
    }
  });

  group('MeterFollower', () {
    test('moves smoothly between readings and stays close', () {
      final f = MeterFollower();
      var shown = <double>[];
      // 10 m/s, read once a second, drawn at 60 fps.
      for (var s = 0; s < 5; s++) {
        f.update(s * 10.0, s.toDouble());
        for (var k = 1; k <= 60; k++) {
          shown.add(f.advance(1 / 60, s + k / 60));
        }
      }
      shown = shown.sublist(120); // once it knows the speed
      for (var i = 1; i < shown.length; i++) {
        final step = shown[i] - shown[i - 1];
        expect(step, inInclusiveRange(0, 0.5)); // no jumps or reversing
      }
      expect(shown.last, closeTo(50, 1));
    });

    test('jumps straight to a restart', () {
      final f = MeterFollower()
        ..update(500, 0)
        ..update(510, 1)
        ..update(0, 2);
      expect(f.advance(1 / 60, 2), closeTo(0, 1e-9));
    });
  });

  test('a long course keeps a bounded number of points', () {
    expect(WorldPath.of(courseById('coast-loop-v1')!.route).points.length,
        lessThanOrEqualTo(20001));
  });
}
