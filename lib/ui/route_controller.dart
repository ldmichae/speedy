import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/ride_recording.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import 'recorder_controller.dart';

/// Overridable so tests never touch the network.
final routeSnapperProvider = Provider<RouteSnapper>((ref) => OsrmSnapper());

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
class RouteRun {
  const RouteRun(this.route, this.origin);
  final SavedRoute route;
  final double origin;
}

final routeRunProvider = NotifierProvider<RouteRunner, RouteRun?>(RouteRunner.new);

class RouteRunner extends Notifier<RouteRun?> {
  @override
  RouteRun? build() {
    ref.listen(recorderProvider.select((r) => r.status), (_, s) {
      if (s == RecStatus.idle) stop(); // saved or discarded
    });
    return null;
  }

  /// Starts recording (or resumes it) and puts the rider at the route's start.
  void start(SavedRoute route) {
    ref.read(recorderProvider.notifier).startOrResume();
    state = RouteRun(route, ref.read(liveRideStatsProvider).distanceMeters);
  }

  void stop() => state = null;
}

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
