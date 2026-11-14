import 'dart:math' as math;

import 'units.dart';

/// Height along a route: [elevations] (metres) at [distances] (metres from
/// the start, increasing).
class ElevationProfile {
  ElevationProfile._(this.distances, this.elevations);

  /// Builds a profile from raw samples, lightly smoothed: elevation data is
  /// ~30-90 m resolution, so single-sample spikes would read as walls.
  factory ElevationProfile.fromSamples(List<double> distances, List<double> raw) {
    assert(distances.length == raw.length && raw.length >= 2);
    final e = [
      for (var i = 0; i < raw.length; i++)
        // The ends stay as measured: averaging there would bias them.
        if (i == 0 || i == raw.length - 1)
          raw[i]
        else
          _avg(raw, i - 1, i + 1),
    ];
    return ElevationProfile._(List.of(distances), e);
  }

  static double _avg(List<double> v, int a, int b) {
    var s = 0.0;
    for (var i = a; i <= b; i++) {
      s += v[i];
    }
    return s / (b - a + 1);
  }

  final List<double> distances;
  final List<double> elevations;

  double get lengthMeters => distances.last;
  double get minElevation => elevations.reduce(math.min);
  double get maxElevation => elevations.reduce(math.max);

  /// Total metres climbed / descended.
  double get climb => _sum((d) => d > 0 ? d : 0);
  double get descent => _sum((d) => d < 0 ? -d : 0);

  double _sum(double Function(double) f) {
    var s = 0.0;
    for (var i = 1; i < elevations.length; i++) {
      s += f(elevations[i] - elevations[i - 1]);
    }
    return s;
  }

  /// Height after [meters] along the route, clamped to the ends.
  double elevationAt(double meters) {
    if (meters <= distances.first) return elevations.first;
    if (meters >= distances.last) return elevations.last;
    var lo = 1, hi = distances.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (distances[mid] < meters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final span = distances[lo] - distances[lo - 1];
    final f = span == 0 ? 0.0 : (meters - distances[lo - 1]) / span;
    return elevations[lo - 1] + (elevations[lo] - elevations[lo - 1]) * f;
  }

  /// Road grade in percent over the next [span] metres (the last [span] at
  /// the end of the route), which is steadier than a point-to-point slope.
  double gradeAt(double meters, {double span = 150}) {
    final s = math.min(span, lengthMeters);
    if (s <= 0) return 0;
    final from = meters.clamp(0.0, lengthMeters - s).toDouble();
    return (elevationAt(from + s) - elevationAt(from)) / s * 100;
  }

  /// Steepest climb and descent grade, in percent (descent is negative).
  (double, double) get gradeRange {
    var up = 0.0, down = 0.0;
    for (var m = 0.0; m <= lengthMeters; m += 50) {
      final g = gradeAt(m);
      up = math.max(up, g);
      down = math.min(down, g);
    }
    return (up, down);
  }

  Map<String, Object?> toJson() => {
        'd': [for (final d in distances) d.round()],
        'e': [for (final e in elevations) (e * 10).round() / 10],
      };

  /// Null if [j] is unusable; the route then simply has no profile.
  static ElevationProfile? fromJson(Object? j) {
    if (j is! Map || j['d'] is! List || j['e'] is! List) return null;
    final d = j['d'] as List, e = j['e'] as List;
    if (d.length != e.length || d.length < 2) return null;
    if (d.any((x) => x is! num) || e.any((x) => x is! num)) return null;
    final dd = [for (final x in d) (x as num).toDouble()];
    for (var i = 1; i < dd.length; i++) {
      if (dd[i] < dd[i - 1]) return null;
    }
    return ElevationProfile._(dd, [for (final x in e) (x as num).toDouble()]);
  }
}

/// "↑ 180 m  ↓ 175 m  max 6.2%" for a profile.
String elevationSummary(ElevationProfile p, UnitSystem u) {
  final (up, _) = p.gradeRange;
  return '↑ ${elevationText(p.climb, u)}   ↓ ${elevationText(p.descent, u)}   '
      'steepest ${up.toStringAsFixed(1)}%';
}
