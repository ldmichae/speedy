/// One interval: [seconds] long, going from [from] to [to] (equal = flat).
/// Values are watts, or percent of FTP inside an unresolved [Plan].
class PlanStep {
  const PlanStep(this.seconds, this.from, [int? to]) : to = to ?? from;
  final int seconds;
  final int from;
  final int to;

  Map<String, Object?> toJson() => {'s': seconds, 'a': from, 'b': to};
}

/// [steps] ridden [repeat] times in a row. A plain step is a block of one.
class PlanBlock {
  const PlanBlock(this.steps, {this.repeat = 1});
  final List<PlanStep> steps;
  final int repeat;
}

/// A named workout: blocks of steps, in watts or in percent of FTP.
class Plan {
  const Plan(this.name, this.blocks, {this.percent = false});
  final String name;
  final List<PlanBlock> blocks;
  final bool percent;

  /// Every step in ride order, repeats unrolled, values in the plan's unit.
  List<PlanStep> expand() => [
        for (final b in blocks)
          for (var i = 0; i < b.repeat; i++) ...b.steps,
      ];

  int get totalSeconds => expand().totalSeconds;

  /// Steps in watts. A percent plan needs [ftp]; null [ftp] is an error there.
  List<PlanStep> resolve(int? ftp) {
    if (!percent) return expand();
    final f = ftp!;
    int w(int pct) => (pct * f / 100).round();
    return [for (final s in expand()) PlanStep(s.seconds, w(s.from), w(s.to))];
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'pct': percent,
        'blocks': [
          for (final b in blocks)
            {'n': b.repeat, 'steps': [for (final s in b.steps) s.toJson()]}
        ],
      };

  /// Null if [j] is not a usable plan (stored data is never trusted). Also
  /// reads the first, flat format: `steps` of `{s, w}`.
  static Plan? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String) return null;
    PlanStep? step(Object? s) {
      if (s is! Map || s['s'] is! int || s['s'] <= 0) return null;
      final a = s['a'] ?? s['w'], b = s['b'] ?? a;
      if (a is! int || b is! int || a < 0 || b < 0) return null;
      return PlanStep(s['s'] as int, a, b);
    }

    List<PlanStep>? steps(Object? l) {
      if (l is! List || l.isEmpty) return null;
      final out = l.map(step).toList();
      return out.contains(null) ? null : out.cast<PlanStep>();
    }

    final blocks = <PlanBlock>[];
    if (j['blocks'] is List) {
      for (final b in j['blocks'] as List) {
        final s = b is Map ? steps(b['steps']) : null;
        if (s == null || b['n'] is! int || b['n'] < 1) return null;
        blocks.add(PlanBlock(s, repeat: b['n'] as int));
      }
    } else {
      final s = steps(j['steps']);
      if (s == null) return null;
      blocks.addAll([for (final x in s) PlanBlock([x])]);
    }
    return blocks.isEmpty ? null : Plan(j['name'] as String, blocks, percent: j['pct'] == true);
  }
}

extension PlanSteps on List<PlanStep> {
  int get totalSeconds => fold(0, (a, s) => a + s.seconds);

  /// Index of the step running [elapsed] seconds in; null once finished.
  int? indexAt(int elapsed) {
    var end = 0;
    for (var i = 0; i < length; i++) {
      end += this[i].seconds;
      if (elapsed < end) return i;
    }
    return null;
  }

  /// Seconds elapsed when step [i] ends.
  int endOf(int i) => take(i + 1).fold(0, (a, s) => a + s.seconds);

  /// Target at [elapsed], ramps interpolated; null once finished.
  int? wattsAt(int elapsed) {
    final i = indexAt(elapsed);
    if (i == null) return null;
    final s = this[i], into = elapsed - (endOf(i) - s.seconds);
    return (s.from + (s.to - s.from) * into / s.seconds).round();
  }

  /// Corner points (seconds, watts) for drawing, starting at [origin].
  List<(double, double)> outline(double origin) {
    final pts = <(double, double)>[];
    var t = origin;
    for (final s in this) {
      pts.add((t, s.from.toDouble()));
      t += s.seconds;
      pts.add((t, s.to.toDouble()));
    }
    return pts;
  }
}
