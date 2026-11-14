import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/ride_recording.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import '../devices/trainer_session.dart';
import 'plan_controller.dart';
import 'recorder_controller.dart';
import 'trainer_controller.dart';

/// Overridable so tests never touch the network.
final routeSnapperProvider = Provider<RouteSnapper>((ref) => OsrmSnapper());

/// Overridable so tests never touch the network.
final elevationSourceProvider =
    Provider<ElevationSource>((ref) => OpenMeteoElevation());

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
}

/// A route being ridden. [origin] is the ride distance (metres) at which the
/// route's start line sits, so riding it mid-recording starts it at zero.
/// With [simulate] the trainer applies the route's grade as resistance.
class RouteRun {
  const RouteRun(this.route, this.origin, {this.simulate = false});
  final SavedRoute route;
  final double origin;
  final bool simulate;
}

final routeRunProvider = NotifierProvider<RouteRunner, RouteRun?>(RouteRunner.new);

class RouteRunner extends Notifier<RouteRun?> {
  @override
  RouteRun? build() {
    ref.listen(recorderProvider.select((r) => r.status), (_, s) {
      if (s == RecStatus.idle) stop(); // saved or discarded
    });
    // Once a second while riding: follow the road's grade.
    ref.listen(recorderProvider, (_, __) => _sync());
    return null;
  }

  /// Starts recording (or resumes it) and puts the rider at the route's
  /// start. [simulate] needs elevation and takes the target from any plan.
  void start(SavedRoute route, {bool simulate = false}) {
    final sim = simulate && route.elevation != null;
    if (sim) ref.read(planRunProvider.notifier).stop();
    ref.read(recorderProvider.notifier).startOrResume();
    state = RouteRun(route, ref.read(liveRideStatsProvider).distanceMeters,
        simulate: sim);
    _sync();
  }

  /// Back to ERG at the last target; the route and map carry on.
  void endSimulation() {
    final r = state;
    if (r == null || !r.simulate) return;
    state = RouteRun(r.route, r.origin);
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
    final ele = r?.route.elevation;
    if (r == null || !r.simulate || ele == null) return;
    if (ref.read(recorderProvider).status != RecStatus.recording) return;
    final meters = (ref.read(liveRideStatsProvider).distanceMeters - r.origin)
        .clamp(0.0, r.route.lengthMeters)
        .toDouble();
    final grade =
        meters >= r.route.lengthMeters ? 0.0 : ele.gradeAt(meters); // flat at the finish
    final t = ref.read(trainerControllerProvider);
    // Compared with what the trainer was last told, so a reconnect re-sends.
    if (t.gradePercent == null || (t.gradePercent! - TrainerSession.clampGrade(grade)).abs() >= 0.2) {
      ref.read(trainerControllerProvider.notifier).setGrade(grade);
    }
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

/// Where the rider is on the route being ridden.
class RouteProgress {
  const RouteProgress(this.route, this.meters, this.position);
  final SavedRoute route;
  final double meters;
  final LatLng position;

  double get fraction => route.lengthMeters == 0 ? 1 : meters / route.lengthMeters;
  bool get finished => meters >= route.lengthMeters;
}

/// Null when no route is being ridden. Position follows distance ridden,
/// which the recorder already integrates from the trainer's speed.
final routeProgressProvider = Provider<RouteProgress?>((ref) {
  final run = ref.watch(routeRunProvider);
  if (run == null) return null;
  final ridden = ref.watch(liveRideStatsProvider).distanceMeters - run.origin;
  final m = ridden.clamp(0.0, run.route.lengthMeters).toDouble();
  return RouteProgress(run.route, m, run.route.positionAt(m));
});
