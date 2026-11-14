import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/elevation.dart';
import '../core/ride_history_store.dart';
import '../core/route_service.dart';
import '../core/tour.dart';
import 'route_controller.dart' show elevationSourceProvider;

/// Overridable so tests do not touch the filesystem.
final tourStoreProvider =
    Provider<RideHistoryStore>((ref) => createTourStore());

final toursProvider =
    AsyncNotifierProvider<ToursController, List<Tour>>(ToursController.new);

class ToursController extends AsyncNotifier<List<Tour>> {
  @override
  Future<List<Tour>> build() async {
    final raw = await ref.read(tourStoreProvider).loadAll();
    final tours = <Tour>[];
    for (final s in raw) {
      try {
        final t = Tour.fromJson(jsonDecode(s));
        if (t != null)
          tours.add(t); // an unreadable tour must not hide the rest
      } catch (_) {}
    }
    tours.sort((a, b) => a.id.compareTo(b.id));
    return tours;
  }

  List<Tour> get _tours => state.valueOrNull ?? const [];

  Tour? byId(String id) => _tours.where((t) => t.id == id).firstOrNull;

  /// Saves [t] (new or changed). Throws if the store cannot write.
  Future<void> upsert(Tour t) async {
    await ref.read(tourStoreProvider).save(t.id, jsonEncode(t.toJson()));
    final i = _tours.indexWhere((x) => x.id == t.id);
    state = AsyncData(i < 0 ? [..._tours, t] : ([..._tours]..[i] = t));
  }

  Future<void> delete(String id) async {
    await ref.read(tourStoreProvider).delete(id);
    state = AsyncData([..._tours.where((t) => t.id != id)]);
  }

  /// Stores a looked-up profile on one stage, on top of the tour as it is
  /// now (the tour may have been edited while the lookup ran).
  Future<void> setStageElevation(
      String id, int index, ElevationProfile e) async {
    final t = byId(id);
    if (t == null || index >= t.stageCount) return;
    await upsert(t.withStage(index, t.stage(index).withElevation(e)));
  }

  Future<void> markCompleted(String id, int index) async {
    final t = byId(id);
    if (t == null || t.completed.contains(index)) return;
    await upsert(t.withCompleted(index));
  }
}

/// A stage whose elevation is being fetched, or whose fetch failed.
class StageLoad {
  const StageLoad.loading()
      : loading = true,
        message = null;
  const StageLoad.failed(this.message) : loading = false;
  final bool loading;
  final String? message;
}

final tourElevationProvider =
    NotifierProvider<TourElevation, Map<String, StageLoad>>(TourElevation.new);

String stageKey(String tourId, int index) => '$tourId#$index';

/// Fetches stage elevation only when asked (a button) or when a ride is about
/// to need it. Never retries by itself: a failed stage stays failed until
/// the rider taps Load again, and a rate limit blocks all lookups until it
/// has passed.
class TourElevation extends Notifier<Map<String, StageLoad>> {
  DateTime? _blockedUntil;

  @override
  Map<String, StageLoad> build() {
    return {};
  }

  /// Called each second of a tour ride: have the stage you are in, and (from
  /// 70% through it) the next one, ready. A stage that already failed is left
  /// alone until the rider asks again.
  void prefetch(Tour c, double meters) {
    final i = c.stageAt(meters);
    final into = (meters - c.stageStart(i)) / c.stage(i).lengthMeters;
    for (final idx in [i, if (into >= 0.7 && i + 1 < c.stageCount) i + 1]) {
      if (c.stage(idx).elevation == null && state[stageKey(c.id, idx)] == null) {
        load(c.id, idx);
      }
    }
  }

  void _set(String key, StageLoad? s) {
    final next = {...state};
    s == null ? next.remove(key) : next[key] = s;
    state = next;
  }

  Future<void> load(String tourId, int index) async {
    final key = stageKey(tourId, index);
    if (state[key]?.loading ?? false) return;
    final tour = ref.read(toursProvider.notifier).byId(tourId);
    if (tour == null ||
        index >= tour.stageCount ||
        tour.stage(index).elevation != null) {
      return;
    }
    final until = _blockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      _set(key, StageLoad.failed(_busy(until.difference(DateTime.now()))));
      return;
    }
    _set(key, const StageLoad.loading());
    try {
      final e =
          await ref.read(elevationSourceProvider).profile(tour.stage(index));
      await ref
          .read(toursProvider.notifier)
          .setStageElevation(tourId, index, e);
      _set(key, null);
    } on ElevationRateLimited catch (e) {
      _blockedUntil = DateTime.now().add(e.retryAfter);
      _set(key, StageLoad.failed(_busy(e.retryAfter)));
    } catch (_) {
      _set(key, const StageLoad.failed('Could not load elevation.'));
    }
  }

  String _busy(Duration d) =>
      'The elevation service is busy. Try again in ${(d.inSeconds / 60).ceil()} min.';

  /// Every stage that has none yet, one after another (stops if rate limited).
  Future<void> loadAll(String tourId) async {
    final tour = ref.read(toursProvider.notifier).byId(tourId);
    if (tour == null) return;
    for (var i = 0; i < tour.stageCount; i++) {
      if (tour.stage(i).elevation != null) continue;
      await load(tourId, i);
      final until = _blockedUntil;
      if (until != null && DateTime.now().isBefore(until)) return;
    }
  }
}
