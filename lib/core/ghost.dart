/// One finished ride of a Compete course: where the rider was and when
/// (seconds since the start line against metres along the course), and how
/// hard they were working (power and heart rate, with their weight for
/// W/kg). All of it is shared with the ghost; the effort is optional, so
/// ghosts without it still race.
class Ghost {
  Ghost({
    required this.id,
    required this.course,
    required this.name,
    required this.t,
    required this.d,
    List<int?>? power,
    List<int?>? hr,
    this.kg,
    this.mine = false,
  })  : power = power ?? List.filled(t.length, null),
        hr = hr ?? List.filled(t.length, null),
        assert(t.length == d.length && t.length >= 2);

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

  /// Watts (3 s average) and beats per minute at each point; null where the
  /// trainer sent none. Same length as [t].
  final List<int?> power, hr;

  /// Rider weight when it was ridden, for W/kg; null if not set.
  final double? kg;

  double get seconds => t.last;
  double get meters => d.last;

  Ghost named(String name, {bool mine = false}) => Ghost(
      id: id,
      course: course,
      name: name,
      t: t,
      d: d,
      power: power,
      hr: hr,
      kg: kg,
      mine: mine);

  /// Where the ghost is [s] seconds in; stays at the finish afterwards.
  double distanceAt(double s) => _lerp(t, d, s);

  /// When the ghost was [m] metres in; null if it never got that far.
  double? timeAt(double m) => m > meters ? null : _lerp(d, t, m);

  /// Power and heart rate as last recorded at or before [s] seconds.
  ({int? watts, int? bpm}) effortAt(double s) {
    var lo = 0, hi = t.length - 1;
    if (s < t.first) return (watts: null, bpm: null);
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      t[mid] <= s ? lo = mid : hi = mid - 1;
    }
    return (watts: power[lo], bpm: hr[lo]);
  }

  Map<String, Object?> toJson() {
    final effort = power.any((x) => x != null) || hr.any((x) => x != null);
    return {
      'v': 1,
      'id': id,
      'course': course,
      'name': name,
      if (mine) 'mine': true,
      if (kg != null) 'kg': (kg! * 10).round() / 10,
      // [t, d] or [t, d, watts, bpm]; older apps read the first two only.
      'pts': [
        for (var i = 0; i < t.length; i++)
          [
            (t[i] * 10).round() / 10,
            (d[i] * 10).round() / 10,
            if (effort) ...[power[i], hr[i]],
          ]
      ],
    };
  }

  /// Null if [j] is not a usable ghost (shared files are never trusted).
  /// Effort values out of any human range are dropped, not trusted.
  static Ghost? fromJson(Object? j) {
    try {
      if (j is! Map || j['v'] != 1) return null;
      final id = j['id'], course = j['course'], name = j['name'], pts = j['pts'];
      if (id is! String || course is! String || name is! String) return null;
      if (pts is! List || pts.length < 2) return null;
      int? within(Object? v, int max) =>
          v is num && v.isFinite && v >= 0 && v <= max ? v.round() : null;
      final t = <double>[], d = <double>[];
      final power = <int?>[], hr = <int?>[];
      for (final p in pts) {
        final a = (p as List)[0], b = p[1];
        if (a is! num || b is! num || !a.isFinite || !b.isFinite) return null;
        if (a < 0 || b < 0) return null;
        // Time and distance only ever grow.
        if (t.isNotEmpty && (a < t.last || b < d.last)) return null;
        t.add(a.toDouble());
        d.add(b.toDouble());
        power.add(p.length > 2 ? within(p[2], 3000) : null);
        hr.add(p.length > 3 ? within(p[3], 250) : null);
      }
      if (d.last <= 0) return null;
      final kg = j['kg'];
      return Ghost(
          id: id,
          course: course,
          name: name,
          t: t,
          d: d,
          power: power,
          hr: hr,
          kg: kg is num && kg >= 20 && kg <= 250 ? kg.toDouble() : null,
          mine: j['mine'] == true);
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
  final power = <int?>[null], hr = <int?>[null];

  bool get finished => d.last >= length;

  /// Adds where the rider is [secs] after the start line, and how hard they
  /// are working. The tick that crosses the line is cut back to the moment
  /// the line was reached.
  void add(double secs, double meters, {int? watts, int? bpm}) {
    if (finished || secs <= t.last || meters < d.last) return;
    if (meters >= length) {
      final f = meters == d.last ? 1.0 : (length - d.last) / (meters - d.last);
      t.add(t.last + (secs - t.last) * f);
      d.add(length);
    } else {
      t.add(secs);
      d.add(meters);
    }
    power.add(watts);
    hr.add(bpm);
  }
}

/// "245 W · 3.4 W/kg · 162 bpm", leaving out what is not known; null if
/// nothing is.
String? effortText(int? watts, int? bpm, double? kg) {
  final parts = [
    if (watts != null) '$watts W',
    if (watts != null && kg != null) '${(watts / kg).toStringAsFixed(1)} W/kg',
    if (bpm != null) '$bpm bpm',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
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
