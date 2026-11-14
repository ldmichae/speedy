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

/// A drawn route: the points the rider clicked, and the road-snapped
/// [path] between them (stored, so riding it needs no network).
class SavedRoute {
  SavedRoute(this.name, this.waypoints, this.path, {this.elevation})
      : assert(path.length >= 2);
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

  double get lengthMeters => cumulative.last;

  /// Where you are after riding [meters] along the route; clamped to the
  /// ends, so a finished route stays at its last point.
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
        'wp': [for (final p in waypoints) [p.latitude, p.longitude]],
        'path': [for (final p in path) [p.latitude, p.longitude]],
        if (elevation != null) 'ele': elevation!.toJson(),
      };

  /// Null if [j] is not a usable route (stored data is never trusted).
  static SavedRoute? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String) return null;
    List<LatLng>? points(Object? l) {
      if (l is! List) return null;
      final out = <LatLng>[];
      for (final p in l) {
        if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) return null;
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


/// Metres to a readable distance, e.g. "850 m" or "12.4 km".
String routeDistanceText(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 2 : 1)} km';

