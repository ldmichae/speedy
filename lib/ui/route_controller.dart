import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/ride_recording.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import '../core/terrain_cache.dart';
import '../core/terrain_tiles.dart';
import '../core/tour.dart';
import '../devices/trainer_session.dart';
import 'plan_controller.dart';
import 'recorder_controller.dart';
import 'tour_controller.dart';
import 'trainer_controller.dart';

/// Overridable so tests never touch the network.
final routeSnapperProvider = Provider<RouteSnapper>((ref) => OsrmSnapper());

/// Terrain tiles first (cheap, cached, dense) on native; Open-Meteo when the
/// tiles fail, and on web where a browser cannot read them. Overridable so
/// tests never touch the network.
final elevationSourceProvider = Provider<ElevationSource>((ref) {
  final meteo = OpenMeteoElevation();
  if (kIsWeb) return meteo;
  final client = http.Client();
  ref.onDispose(client.close);
  return CompositeElevation(
    TerrainTileElevation(
        fetch: httpTileFetcher(client), cache: createTerrainCache()),
    meteo,
  );
});

final routesProvider =
    NotifierProvider<RoutesController, List<SavedRoute>>(RoutesController.new);

class RoutesController extends PersistedNotifier<List<SavedRoute>> {
  static const _key = 'routes';

  @override
  List<SavedRoute> get defaults => const [];

  @override
  List<SavedRoute>? read(SharedPreferences p) {
    try {
      final raw = p.getString(_key);
      if (raw == null) return null;
      return [
        for (final j in jsonDecode(raw) as List) SavedRoute.fromJson(j),
      ].whereType<SavedRoute>().toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SharedPreferences p, List<SavedRoute> v) =>
      p.setString(_key, jsonEncode([for (final r in v) r.toJson()]));

  void add(SavedRoute r) => put([...state, r]);

  void delete(SavedRoute r) => put([...state]..remove(r));

  void replace(SavedRoute old, SavedRoute r) =>
      put([for (final x in state) identical(x, old) ? r : x]);
}

/// A course being ridden (one route, or a tour). [origin] is the ride
/// distance (metres) at which the course's start line sits, so riding
/// mid-recording starts it at zero, or at the chosen stage of a tour.
/// With [simulate] the trainer applies the course's grade as resistance.
class RouteRun {
  const RouteRun(this.course, this.origin, {this.simulate = false});
  final RideCourse course;
  final double origin;
  final bool simulate;
}

final routeRunProvider =
    NotifierProvider<RouteRunner, RouteRun?>(RouteRunner.new);

class RouteRunner extends Notifier<RouteRun?> {
  int _doneUpTo = 0; // tour stages before this index are marked ridden

  @override
  RouteRun? build() {
    ref.listen(recorderProvider.select((r) => r.status), (_, s) {
      if (s == RecStatus.idle) stop(); // saved or discarded
    });
    // Once a second while riding: follow the road's grade.
    ref.listen(recorderProvider, (_, __) => _sync());
    // A tour being ridden gains elevation as stages load: use the new copy.
    ref.listen(toursProvider, (_, next) {
      final r = state, c = r?.course;
      if (r == null || c is! Tour) return;
      final fresh = next.valueOrNull?.where((t) => t.id == c.id).firstOrNull;
      if (fresh != null && !identical(fresh, c)) {
        state = RouteRun(fresh, r.origin, simulate: r.simulate);
      }
    });
    return null;
  }

  /// Starts recording (or resumes it) and puts the rider at the start of
  /// [course], or of [stage] for a tour. [simulate] takes the target from any
  /// plan; where elevation is not loaded yet it rides flat.
  void start(RideCourse course, {bool simulate = false, int stage = 0}) {
    final sim =
        simulate && (course.stageCount > 1 || course.elevationAt(0) != null);
    if (sim) ref.read(planRunProvider.notifier).stop();
    ref.read(recorderProvider.notifier).startOrResume();
    _doneUpTo = stage;
    state = RouteRun(
        course,
        ref.read(liveRideStatsProvider).distanceMeters -
            course.stageStart(stage),
        simulate: sim);
    _sync();
  }

  /// Back to ERG at the last target; the route and map carry on.
  void endSimulation() {
    final r = state;
    if (r == null || !r.simulate) return;
    state = RouteRun(r.course, r.origin);
    _leaveSim();
  }

  void stop() {
    final wasSim = state?.simulate ?? false;
    state = null;
    if (wasSim) _leaveSim();
  }

  void _leaveSim() {
    final t = ref.read(trainerControllerProvider.notifier);
    t.setTarget(ref.read(trainerControllerProvider).targetWatts);
  }

  void _sync() {
    final r = state;
    if (r == null) return;
    if (ref.read(recorderProvider).status != RecStatus.recording) return;
    final len = r.course.lengthMeters;
    final meters = (ref.read(liveRideStatsProvider).distanceMeters - r.origin)
        .clamp(0.0, len)
        .toDouble();
    _markStages(r.course, meters);
    final c = r.course;
    if (c is Tour) ref.read(tourElevationProvider.notifier).prefetch(c, meters);
    if (!r.simulate) return;
    // Flat at the finish, and wherever elevation has not loaded yet.
    final grade = meters >= len ? 0.0 : (r.course.gradeAt(meters) ?? 0.0);
    final t = ref.read(trainerControllerProvider);
    // Compared with what the trainer was last told, so a reconnect re-sends.
    if (t.gradePercent == null ||
        (t.gradePercent! - TrainerSession.clampGrade(grade)).abs() >= 0.2) {
      ref.read(trainerControllerProvider.notifier).setGrade(grade);
    }
  }

  /// Passing the end of a tour stage ticks it off.
  void _markStages(RideCourse c, double meters) {
    if (c is! Tour) return;
    final upTo = meters >= c.lengthMeters ? c.stageCount : c.stageAt(meters);
    for (var i = _doneUpTo; i < upTo; i++) {
      ref.read(toursProvider.notifier).markCompleted(c.id, i);
    }
    if (upTo > _doneUpTo) _doneUpTo = upTo;
  }
}

/// What owns the ERG target, if anything: the manual controls are locked.
enum TargetLock { plan, simulation }

final targetLockProvider = Provider<TargetLock?>((ref) {
  if (ref.watch(planRunProvider) != null) return TargetLock.plan;
  if (ref.watch(routeRunProvider.select((r) => r?.simulate ?? false))) {
    return TargetLock.simulation;
  }
  return null;
});

/// Where the rider is on the course being ridden.
class RouteProgress {
  const RouteProgress(this.course, this.meters, this.position);
  final RideCourse course;
  final double meters;
  final LatLng position;

  double get fraction =>
      course.lengthMeters == 0 ? 1 : meters / course.lengthMeters;
  bool get finished => meters >= course.lengthMeters;

  /// The stage you are in, and how far through / from the end of it.
  int get stage => course.stageAt(meters);
  double get stageMeters => meters - course.stageStart(stage);
  double get stageRemaining =>
      course.stageStart(stage) + course.stage(stage).lengthMeters - meters;
}

/// Null when no route is being ridden. Position follows distance ridden,
/// which the recorder already integrates from the trainer's speed.
final routeProgressProvider = Provider<RouteProgress?>((ref) {
  final run = ref.watch(routeRunProvider);
  if (run == null) return null;
  final ridden = ref.watch(liveRideStatsProvider).distanceMeters - run.origin;
  final m = ridden.clamp(0.0, run.course.lengthMeters).toDouble();
  return RouteProgress(run.course, m, run.course.positionAt(m));
});

/// Which roads new route segments may use. Remembered between sessions.
final roadProfileProvider =
    NotifierProvider<RoadProfileController, RoadProfile>(
        RoadProfileController.new);

class RoadProfileController extends PersistedNotifier<RoadProfile> {
  static const _key = 'roadProfile';

  @override
  RoadProfile get defaults => RoadProfile.car;

  @override
  RoadProfile? read(SharedPreferences p) {
    final name = p.getString(_key);
    return RoadProfile.values.where((r) => r.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences p, RoadProfile v) =>
      p.setString(_key, v.name);

  void set(RoadProfile v) => put(v);
}
