/// One finished ride of a Compete course, reduced to where the rider was and
/// when: seconds since the start line against metres along the course. That
/// is all a race needs, and all that is shared (no power or heart rate).
class Ghost {
  Ghost({
    required this.id,
    required this.course,
    required this.name,
    required this.t,
    required this.d,
    this.mine = false,
  }) : assert(t.length == d.length && t.length >= 2);

  /// Unique per effort (when it was ridden); the same file imported twice
  /// is one ghost.
  final String id;

  /// The [Course] id it was ridden on.
  final String course;
  final String name;

  /// Your own effort, as opposed to one imported from someone else.
  final bool mine;

  /// Seconds and metres, same length, non-decreasing, ending at the finish.
  final List<double> t, d;

  double get seconds => t.last;
  double get meters => d.last;

  Ghost named(String name, {bool mine = false}) =>
      Ghost(id: id, course: course, name: name, t: t, d: d, mine: mine);

  /// Where the ghost is [s] seconds in; stays at the finish afterwards.
  double distanceAt(double s) => _lerp(t, d, s);

  /// When the ghost was [m] metres in; null if it never got that far.
  double? timeAt(double m) => m > meters ? null : _lerp(d, t, m);

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'course': course,
        'name': name,
        if (mine) 'mine': true,
        'pts': [
          for (var i = 0; i < t.length; i++)
            [(t[i] * 10).round() / 10, (d[i] * 10).round() / 10]
        ],
      };

  /// Null if [j] is not a usable ghost (shared files are never trusted).
  static Ghost? fromJson(Object? j) {
    try {
      if (j is! Map || j['v'] != 1) return null;
      final id = j['id'], course = j['course'], name = j['name'], pts = j['pts'];
      if (id is! String || course is! String || name is! String) return null;
      if (pts is! List || pts.length < 2) return null;
      final t = <double>[], d = <double>[];
      for (final p in pts) {
        final a = (p as List)[0], b = p[1];
        if (a is! num || b is! num || !a.isFinite || !b.isFinite) return null;
        if (a < 0 || b < 0) return null;
        // Time and distance only ever grow.
        if (t.isNotEmpty && (a < t.last || b < d.last)) return null;
        t.add(a.toDouble());
        d.add(b.toDouble());
      }
      if (d.last <= 0) return null;
      return Ghost(
          id: id, course: course, name: name, t: t, d: d, mine: j['mine'] == true);
    } catch (_) {
      return null;
    }
  }
}

/// Builds a ghost while a course is ridden: one point per recorder tick.
class GhostTrace {
  GhostTrace(this.length);

  /// The course length; the trace ends when it is reached.
  final double length;
  final t = <double>[0], d = <double>[0];

  bool get finished => d.last >= length;

  /// Adds where the rider is [secs] after the start line. The tick that
  /// crosses the line is cut back to the moment the line was reached.
  void add(double secs, double meters) {
    if (finished || secs <= t.last || meters < d.last) return;
    if (meters >= length) {
      final f = meters == d.last ? 1.0 : (length - d.last) / (meters - d.last);
      t.add(t.last + (secs - t.last) * f);
      d.add(length);
    } else {
      t.add(secs);
      d.add(meters);
    }
  }
}

/// Linear interpolation of [ys] at [x] along ascending [xs]; clamped.
double _lerp(List<double> xs, List<double> ys, double x) {
  if (x <= xs.first) return ys.first;
  if (x >= xs.last) return ys.last;
  var lo = 1, hi = xs.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    xs[mid] < x ? lo = mid + 1 : hi = mid;
  }
  final span = xs[lo] - xs[lo - 1];
  return span == 0
      ? ys[lo]
      : ys[lo - 1] + (ys[lo] - ys[lo - 1]) * (x - xs[lo - 1]) / span;
}

/// How the rider stands against a ghost right now.
class GhostGap {
  const GhostGap(this.meters, this.seconds);

  /// Positive: the rider is ahead of the ghost.
  final double meters;

  /// Time ahead (positive) at the rider's distance; null once the rider has
  /// gone further than the ghost ever did.
  final double? seconds;

  bool get ahead => meters >= 0;
}

GhostGap gapTo(Ghost g, {required double elapsed, required double riderMeters}) {
  final at = g.timeAt(riderMeters);
  return GhostGap(
      riderMeters - g.distanceAt(elapsed), at == null ? null : at - elapsed);
}

/// "12 s ahead" / "40 m behind": seconds when there are any, as that is how
/// races are read.
String gapText(GhostGap g) {
  final s = g.seconds;
  final v = s != null && s.abs() >= 1 ? s : null;
  final n = v == null ? g.meters.abs() : v.abs();
  return '${n.round()} ${v == null ? 'm' : 's'} ${g.ahead ? 'ahead' : 'behind'}';
}
