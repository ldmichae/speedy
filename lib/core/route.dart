import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'elevation.dart';

const _dist = Distance(roundResult: false);

/// Length of a polyline in metres.
double pathLength(List<LatLng> path) {
  var m = 0.0;
  for (var i = 1; i < path.length; i++) {
    m += _dist(path[i - 1], path[i]);
  }
  return m;
}

/// Anything that can be ridden: one route, or a tour of stages. The ride
/// code (position, grade, the map tile) only ever sees this.
abstract class RideCourse {
  String get name;
  double get lengthMeters;

  /// Where you are after riding [meters]; clamped to the ends.
  LatLng positionAt(double meters);

  /// Height / road grade (%) there, or null while elevation is not loaded.
  double? elevationAt(double meters);
  double? gradeAt(double meters);

  /// A route is one stage; a tour has many. [stageAt] is the index you are in.
  int get stageCount;
  int stageAt(double meters);
  SavedRoute stage(int index);

  /// Metres from the course start to the start of stage [index].
  double stageStart(int index);
}

/// Douglas-Peucker: drops points that lie within [toleranceMeters] of the
/// line between the ones kept. Ends are always kept. Iterative, so a 50k
/// point path cannot overflow the stack.
List<LatLng> simplifyPath(List<LatLng> path, {double toleranceMeters = 5}) {
  if (path.length <= 2) return List.of(path);
  // Flat local projection (metres): fine over the length of a stage.
  final lat0 = path.first.latitudeInRad;
  const r = 6371000.0;
  final xs = [for (final p in path) r * p.longitudeInRad * math.cos(lat0)];
  final ys = [for (final p in path) r * p.latitudeInRad];
  final keep = List<bool>.filled(path.length, false)
    ..[0] = true
    ..[path.length - 1] = true;
  final stack = <(int, int)>[(0, path.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var far = -1;
    var farDist = toleranceMeters;
    final dx = xs[b] - xs[a], dy = ys[b] - ys[a];
    final len2 = dx * dx + dy * dy;
    for (var i = a + 1; i < b; i++) {
      final t = len2 == 0
          ? 0.0
          : (((xs[i] - xs[a]) * dx + (ys[i] - ys[a]) * dy) / len2)
              .clamp(0.0, 1.0);
      final px = xs[a] + t * dx - xs[i], py = ys[a] + t * dy - ys[i];
      final d = math.sqrt(px * px + py * py);
      if (d > farDist) {
        farDist = d;
        far = i;
      }
    }
    if (far >= 0) {
      keep[far] = true;
      stack
        ..add((a, far))
        ..add((far, b));
    }
  }
  return [
    for (var i = 0; i < path.length; i++)
      if (keep[i]) path[i]
  ];
}

/// A drawn route: the points the rider clicked, and the road-snapped
/// [path] between them (stored, so riding it needs no network).
class SavedRoute implements RideCourse {
  SavedRoute(this.name, this.waypoints, this.path, {this.elevation})
      : assert(path.length >= 2);
  @override
  final String name;
  final List<LatLng> waypoints;
  final List<LatLng> path;

  /// Null until fetched, or if the fetch failed.
  final ElevationProfile? elevation;

  SavedRoute withElevation(ElevationProfile? e) =>
      SavedRoute(name, waypoints, path, elevation: e);

  /// Metres from the start to each point of [path].
  late final List<double> cumulative = () {
    final c = <double>[0];
    for (var i = 1; i < path.length; i++) {
      c.add(c.last + _dist(path[i - 1], path[i]));
    }
    return c;
  }();

  @override
  double get lengthMeters => cumulative.last;

  @override
  double? elevationAt(double meters) => elevation?.elevationAt(meters);
  @override
  double? gradeAt(double meters) => elevation?.gradeAt(meters);
  @override
  int get stageCount => 1;
  @override
  int stageAt(double meters) => 0;
  @override
  SavedRoute stage(int index) => this;
  @override
  double stageStart(int index) => 0;

  /// Where you are after riding [meters] along the route; clamped to the
  /// ends, so a finished route stays at its last point.
  @override
  LatLng positionAt(double meters) {
    if (meters <= 0) return path.first;
    if (meters >= lengthMeters) return path.last;
    var lo = 1, hi = cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (cumulative[mid] < meters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final span = cumulative[lo] - cumulative[lo - 1];
    final f = span == 0 ? 0.0 : (meters - cumulative[lo - 1]) / span;
    final a = path[lo - 1], b = path[lo];
    return LatLng(a.latitude + (b.latitude - a.latitude) * f,
        a.longitude + (b.longitude - a.longitude) * f);
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'wp': [
          for (final p in waypoints) [p.latitude, p.longitude]
        ],
        'path': [
          for (final p in path) [p.latitude, p.longitude]
        ],
        if (elevation != null) 'ele': elevation!.toJson(),
      };

  /// Null if [j] is not a usable route (stored data is never trusted).
  static SavedRoute? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String) return null;
    List<LatLng>? points(Object? l) {
      if (l is! List) return null;
      final out = <LatLng>[];
      for (final p in l) {
        if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num)
          return null;
        final lat = (p[0] as num).toDouble(), lon = (p[1] as num).toDouble();
        if (lat.abs() > 90 || lon.abs() > 180) return null;
        out.add(LatLng(lat, lon));
      }
      return out;
    }

    final wp = points(j['wp']), path = points(j['path']);
    if (wp == null || path == null || path.length < 2) return null;
    return SavedRoute(j['name'] as String, wp, path,
        elevation: ElevationProfile.fromJson(j['ele']));
  }
}

