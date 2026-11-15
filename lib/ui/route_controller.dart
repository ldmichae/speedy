import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import 'recorder_controller.dart';
import 'ride_session.dart';

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

  void replace(SavedRoute old, SavedRoute r) =>
      put([for (final x in state) identical(x, old) ? r : x]);
}

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
