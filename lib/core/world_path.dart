import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math.dart';

import 'route.dart';

/// A course laid out in local metres for the World view: x east, y up,
/// z north, origin at the start line (height relative to it).
class WorldPath {
  WorldPath._(this.points, this.step, this._origin, this.baseHeight);

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
    Vector3 local(double m) {
      final p = course.positionAt(m);
      return Vector3(
        _r * (p.longitudeInRad - o.longitudeInRad) * cosLat,
        (course.elevationAt(m) ?? h0) - h0,
        _r * (p.latitudeInRad - o.latitudeInRad),
      );
    }

    return WorldPath._(
        [for (var i = 0; i <= n; i++) local(i * step)], step, o, h0);
  }

  static const _r = 6378137.0; // latlong2's, so lengths match the course's

  final LatLng _origin;

  /// Height above sea level of y = 0 (the start line).
  final double baseHeight;

  /// Every [step] metres along the course, start to finish.
  final List<Vector3> points;
  final double step;

  double get length => (points.length - 1) * step;

  /// The map position of local ([x], [z]).
  LatLng latLngOf(double x, double z) => LatLng(
      _origin.latitude + z / _r * radians2Degrees,
      _origin.longitude +
          x / (_r * math.cos(_origin.latitudeInRad)) * radians2Degrees);

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

/// Real ground heights on a square grid of local metres (relative to the
/// start line, like [WorldPath.points]), [n] by [n] posts [cell] apart from
/// ([x0], [z0]); row by row northwards, each row eastwards.
class HeightGrid {
  HeightGrid(this.x0, this.z0, this.cell, this.n, this.heights)
      : assert(heights.length == n * n && n >= 2);

  final double x0, z0, cell;
  final int n;
  final Float64List heights;

  /// Bilinear height at ([x], [z]), clamped to the grid.
  double at(double x, double z) {
    final fx = ((x - x0) / cell).clamp(0.0, n - 1.0);
    final fz = ((z - z0) / cell).clamp(0.0, n - 1.0);
    final c = math.min(fx.floor(), n - 2), r = math.min(fz.floor(), n - 2);
    final tx = fx - c, tz = fz - r;
    double h(int rr, int cc) => heights[rr * n + cc];
    final south = h(r, c) * (1 - tx) + h(r, c + 1) * tx;
    final north = h(r + 1, c) * (1 - tx) + h(r + 1, c + 1) * tx;
    return south * (1 - tz) + north * tz;
  }

  /// Whether this terrain is the ground the [road] runs on: its heights
  /// there are within [tolerance] metres on average. It is not for a Compete
  /// course (a made-up road on the equator, out at sea) or a route whose
  /// heights are not loaded yet.
  bool fits(List<Vector3> road, {double tolerance = 25}) {
    var sum = 0.0, count = 0;
    for (final p in road) {
      if (p.x < x0 || p.z < z0) continue;
      if (p.x > x0 + (n - 1) * cell || p.z > z0 + (n - 1) * cell) continue;
      sum += (at(p.x, p.z) - p.y).abs();
      count++;
    }
    return count > 0 && sum / count <= tolerance;
  }
}

/// Ground height at ([x], [z]): just under the nearest road point, then
/// blending into the real [terrain] if there is one, or into gentle made-up
/// hills. [road] is from [WorldPath.near]; returns the distance to the road
/// as well.
({double y, double road}) groundAt(double x, double z, List<Vector3> road,
    {HeightGrid? terrain}) {
  if (road.isEmpty) {
    return (y: terrain?.at(x, z) ?? -roadDepth, road: double.infinity);
  }
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
  final under = h - roadDepth;
  double smooth(double from, double to) {
    final t = ((d - from) / (to - from)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  if (terrain != null) {
    // Flat under the road, the real slope from 60 m out.
    final t = smooth(10, 60);
    return (y: under + (terrain.at(x, z) - under) * t, road: d);
  }
  final hills = 18 * (math.sin(x / 210) * math.cos(z / 170) + 1) +
      6 * math.sin((x + 2 * z) / 67) * math.cos((x - z) / 53);
  return (y: under + smooth(15, 150) * hills, road: d);
}

/// How far the ground sits under the road surface.
const roadDepth = 0.4;

/// Where trees stand in the square of half-size [half] around ([cx], [cz]):
/// one chance per 25 m cell, the same trees every time a cell is built, and
/// none within 12 m of the road. They stand on [groundAt] with [terrain].
List<({double x, double y, double z, double size})> treesAround(
    double cx, double cz, double half, List<Vector3> road,
    {HeightGrid? terrain}) {
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
      final g = groundAt(x, z, road, terrain: terrain);
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
