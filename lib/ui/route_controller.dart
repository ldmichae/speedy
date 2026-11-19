import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../core/json_store.dart';
import '../core/prefs.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import '../core/tour.dart';
import 'recorder_controller.dart';
import 'ride_session.dart';
import 'tour_controller.dart';

/// Overridable so tests never touch the network.
final routeSnapperProvider = Provider<RouteSnapper>((ref) => OsrmSnapper());

/// Overridable so tests do not touch the filesystem.
final routesStoreProvider =
    Provider<JsonStore>((ref) => createJsonStore('routes'));

final routesProvider =
    NotifierProvider<RoutesController, List<SavedRoute>>(RoutesController.new);

/// The saved routes, kept as one document so edits and deletes can go by
/// identity. Routes used to live in shared preferences; the first load moves
/// them over.
class RoutesController extends Notifier<List<SavedRoute>> {
  static const _doc = 'all';
  static const _legacyKey = 'routes';

  bool _touched = false;
  bool _disposed = false;

  @override
  List<SavedRoute> build() {
    ref.onDispose(() => _disposed = true);
    _load();
    return const [];
  }

  static List<SavedRoute>? _decode(String raw) {
    try {
      return [
        for (final j in jsonDecode(raw) as List) SavedRoute.fromJson(j),
      ].whereType<SavedRoute>().toList();
    } catch (_) {
      return null; // unreadable: start empty rather than crash
    }
  }

  /// A [put] made before this finishes wins over what is stored.
  Future<void> _load() async {
    try {
      final docs = await ref.read(routesStoreProvider).loadAll();
      if (docs.isNotEmpty) {
        final stored = _decode(docs.first);
        if (stored != null && !_touched && !_disposed) state = stored;
        return;
      }
      final p = await prefs();
      final raw = p?.getString(_legacyKey);
      final legacy = raw == null ? null : _decode(raw);
      if (p == null || legacy == null || _disposed) return;
      state = [...legacy, ...state];
      await _save();
      await p.remove(_legacyKey); // only once the new copy is written
    } catch (_) {} // storage is a convenience, never fatal
  }

  Future<void> _save() => ref
      .read(routesStoreProvider)
      .save(_doc, jsonEncode([for (final r in state) r.toJson()]));

  void _put(List<SavedRoute> v) {
    _touched = true;
    state = v;
    _save().catchError((_) {});
  }

  void add(SavedRoute r) => _put([...state, r]);

  void delete(SavedRoute r) => _put([...state]..remove(r));

  void replace(SavedRoute old, SavedRoute r) =>
      _put([for (final x in state) identical(x, old) ? r : x]);
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

/// The tour stage to offer next: set once the stage being ridden is finished
/// and the tour has another after it.
final nextStageProvider = Provider<int?>((ref) {
  final p = ref.watch(routeProgressProvider);
  final c = p?.course;
  if (p == null || !p.finished || c is! Tour) return null;
  final full = ref.watch(toursProvider
      .select((a) => a.valueOrNull?.where((t) => t.id == c.id).firstOrNull));
  return full != null && full.stageCount > c.stageCount ? c.stageCount : null;
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
