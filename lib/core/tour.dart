import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'route.dart';

/// A long ride planned as stages (a day or so each), ridden in order. Every
/// stage is an ordinary [SavedRoute] with its own elevation, loaded when
/// wanted, so a tour of any length never needs everything at once.
class Tour implements RideCourse {
  Tour(this.id, this.name, this.stages, {Set<int>? completed, this.resumeAt})
      : completed = completed ?? <int>{},
        assert(stages.isNotEmpty);

  /// Storage key.
  final String id;
  @override
  final String name;
  final List<SavedRoute> stages;

  /// Indices of stages already ridden to the end.
  final Set<int> completed;

  /// Metres from the tour start where the last ride stopped partway through
  /// a stage; the next ride of that stage starts here. Null if none.
  final double? resumeAt;

  /// The stage [resumeAt] is in.
  int? get resumeStage => resumeAt == null ? null : stageAt(resumeAt!);

  /// Metres from the tour start to the start of each stage, then the total.
  late final List<double> _starts = () {
    final s = <double>[0];
    for (final st in stages) {
      s.add(s.last + st.lengthMeters);
    }
    return s;
  }();

  @override
  double get lengthMeters => _starts.last;
  @override
  int get stageCount => stages.length;
  @override
  SavedRoute stage(int index) => stages[index];
  @override
  double stageStart(int index) => _starts[index];

  @override
  int stageAt(double meters) {
    if (meters <= 0) return 0;
    for (var i = 0; i < stages.length; i++) {
      if (meters < _starts[i + 1]) return i;
    }
    return stages.length - 1;
  }

  @override
  LatLng positionAt(double meters) {
    final i = stageAt(meters);
    return stages[i].positionAt(meters - _starts[i]);
  }

  @override
  double? elevationAt(double meters) {
    final i = stageAt(meters);
    return stages[i].elevation?.elevationAt(meters - _starts[i]);
  }

  /// Grade over the next 150 m, read across stage boundaries; null if either
  /// end is in a stage whose elevation is not loaded yet.
  @override
  double? gradeAt(double meters) {
    final span = math.min(150.0, lengthMeters);
    if (span <= 0) return 0;
    final from = meters.clamp(0.0, lengthMeters - span).toDouble();
    final a = elevationAt(from), b = elevationAt(from + span);
    if (a == null || b == null) return null;
    return (b - a) / span * 100;
  }

  /// Metres of this tour whose elevation is loaded.
  int get stagesWithElevation =>
      stages.where((s) => s.elevation != null).length;

  /// An edit that changes a stage's length drops the resume point (it may
  /// no longer fall where the rider stopped); an elevation update keeps it.
  Tour withStage(int index, SavedRoute stage) => Tour(
      id, name, [...stages]..[index] = stage,
      completed: {...completed},
      resumeAt: stage.lengthMeters == stages[index].lengthMeters ? resumeAt : null);

  /// The tour up to the end of stage [last]: what one ride covers, so the
  /// ride ends at that stage's finish line.
  Tour throughStage(int last) => Tour(id, name, stages.sublist(0, last + 1),
      completed: {...completed}, resumeAt: resumeAt);

  Tour withAddedStage(SavedRoute stage) => Tour(id, name, [...stages, stage],
      completed: {...completed}, resumeAt: resumeAt);

  Tour withoutStage(int index) => Tour(
        id,
        name,
        [...stages]..removeAt(index),
        completed: {
          for (final c in completed)
            if (c != index) c > index ? c - 1 : c
        },
      );

  Tour withCompleted(int index) => Tour(id, name, stages,
      completed: {...completed, index}, resumeAt: resumeAt);

  Tour withResume(double? at) =>
      Tour(id, name, stages, completed: {...completed}, resumeAt: at);

  static const _version = 1;

  Map<String, Object?> toJson() => {
        'v': _version,
        'id': id,
        'name': name,
        'done': completed.toList()..sort(),
        if (resumeAt != null) 'at': resumeAt,
        'stages': [for (final s in stages) s.toJson()],
      };

  /// Null if [j] is not a usable tour (stored data is never trusted).
  static Tour? fromJson(Object? j) {
    if (j is! Map ||
        j['v'] != _version ||
        j['id'] is! String ||
        j['name'] is! String) {
      return null;
    }
    if (j['stages'] is! List) return null;
    final stages = <SavedRoute>[];
    for (final s in j['stages'] as List) {
      final r = SavedRoute.fromJson(s);
      if (r == null) return null;
      stages.add(r);
    }
    if (stages.isEmpty) return null;
    final done = j['done'];
    final at = j['at'];
    final len = stages.fold(0.0, (a, s) => a + s.lengthMeters);
    return Tour(
      j['id'] as String,
      j['name'] as String,
      stages,
      completed: {
        if (done is List)
          for (final d in done)
            if (d is int && d >= 0 && d < stages.length) d
      },
      resumeAt: at is num && at > 0 && at < len ? at.toDouble() : null,
    );
  }
}
