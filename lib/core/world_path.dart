import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'route.dart';

/// A course laid out in local metres for the World view: x east, y up,
/// z north, origin at the start line (height relative to it).
class WorldPath {
  WorldPath._(this.points, this.step);

  /// Samples [course] every [step] metres. A long tour stretches the step so
  /// the road stays a few thousand points.
  factory WorldPath.of(RideCourse course, {double step = 10}) {
    final len = course.lengthMeters;
    step = math.max(step, len / 20000);
    final n = math.max(1, (len / step).ceil());
    step = len == 0 ? 1 : len / n;
    final o = course.positionAt(0);
    final h0 = course.elevationAt(0) ?? 0;
    final cosLat = math.cos(o.latitudeInRad);
    const r = 6378137.0; // latlong2's, so lengths match the course's
    Vector3 local(double m) {
      final p = course.positionAt(m);
      return Vector3(
        r * (p.longitudeInRad - o.longitudeInRad) * cosLat,
        (course.elevationAt(m) ?? h0) - h0,
        r * (p.latitudeInRad - o.latitudeInRad),
      );
    }

    return WorldPath._([for (var i = 0; i <= n; i++) local(i * step)], step);
  }

  /// Every [step] metres along the course, start to finish.
  final List<Vector3> points;
  final double step;

  double get length => (points.length - 1) * step;

  /// The road centre after riding [m] metres, clamped to the ends.
  Vector3 at(double m) {
    final f = (m / step).clamp(0.0, points.length - 1.0);
    final i = math.min(f.floor(), points.length - 2);
    if (i < 0) return points.first.clone();
    return points[i] + (points[i + 1] - points[i]) * (f - i);
  }

  /// Unit direction of travel at [m], flat (y = 0). Looks [span] metres
  /// either way, so a kink in the road does not jerk the camera.
  Vector3 heading(double m, {double span = 8}) {
    final d = at(m + span) - at(m - span)
      ..y = 0;
    return d.length2 < 1e-6 ? Vector3(0, 0, 1) : d.normalized();
  }

  /// Rider's right for a [heading]: facing north (+z) it is east (+x).
  static Vector3 rightOf(Vector3 heading) => Vector3(heading.z, 0, -heading.x);

  /// Road points within [radius] of ([x], [z]) (a square), for building
  /// ground and trees near the rider without scanning the whole course.
  List<Vector3> near(double x, double z, double radius) => [
        for (final p in points)
          if ((p.x - x).abs() < radius && (p.z - z).abs() < radius) p
      ];
}

/// Ground height at ([x], [z]): just under the nearest road point, rising
/// into gentle hills away from the road. [road] is from [WorldPath.near];
/// returns the distance to the road as well.
///
/// shortcut: hills are made up, not the real terrain; use the cached
/// terrain tiles (terrain_tiles.dart) when riders want to see real valleys.
({double y, double road}) groundAt(double x, double z, List<Vector3> road) {
  if (road.isEmpty) return (y: -roadDepth, road: double.infinity);
  var best = double.infinity;
  var h = 0.0;
  for (final p in road) {
    final d = (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z);
    if (d < best) {
      best = d;
      h = p.y;
    }
  }
  final d = math.sqrt(best);
  // 0 on and beside the road, 1 from 150 m out.
  final t = ((d - 15) / 135).clamp(0.0, 1.0);
  final ramp = t * t * (3 - 2 * t);
  final hills = 18 * (math.sin(x / 210) * math.cos(z / 170) + 1) +
      6 * math.sin((x + 2 * z) / 67) * math.cos((x - z) / 53);
  return (y: h - roadDepth + ramp * hills, road: d);
}

/// How far the ground sits under the road surface.
const roadDepth = 0.4;

/// Where trees stand in the square of half-size [half] around ([cx], [cz]):
/// one chance per 25 m cell, the same trees every time a cell is built, and
/// none within 12 m of the road.
List<({double x, double y, double z, double size})> treesAround(
    double cx, double cz, double half, List<Vector3> road) {
  const cell = 25.0;
  final out = <({double x, double y, double z, double size})>[];
  final i0 = ((cx - half) / cell).floor(), i1 = ((cx + half) / cell).floor();
  final j0 = ((cz - half) / cell).floor(), j1 = ((cz + half) / cell).floor();
  for (var i = i0; i <= i1; i++) {
    for (var j = j0; j <= j1; j++) {
      final rng = math.Random(i * 73856093 ^ j * 19349663);
      if (rng.nextDouble() > 0.35) continue;
      final x = (i + rng.nextDouble()) * cell,
          z = (j + rng.nextDouble()) * cell;
      final g = groundAt(x, z, road);
      if (g.road < 12) continue;
      out.add((x: x, y: g.y, z: z, size: 0.7 + rng.nextDouble() * 0.8));
    }
  }
  return out;
}

/// Turns the distance ridden, which arrives a few times a second, into a
/// smooth position for every frame: runs at the latest speed and eases out
/// any error instead of jumping.
class MeterFollower {
  double _shown = 0, _target = 0, _speed = 0;
  double? _at; // seconds, when [_target] arrived

  /// A new reading of [meters] at [seconds].
  void update(double meters, double seconds) {
    final at = _at;
    if (at == null || meters < _target || seconds - at > 5) {
      _shown = meters; // first reading, restart or long gap: no easing
      _speed = 0;
    } else if (seconds > at) {
      _speed = (meters - _target) / (seconds - at);
    }
    _target = meters;
    _at = seconds;
  }

  /// Where to draw the rider [dt] seconds after the last frame, at [now].
  double advance(double dt, double now) {
    final at = _at;
    if (at == null) return _shown;
    // Where the rider should be now, at most a second past the reading.
    final aim = _target + _speed * math.min(now - at, 1.0);
    _shown += _speed * dt;
    _shown += (aim - _shown) * math.min(1.0, dt * 3);
    return _shown;
  }
}
