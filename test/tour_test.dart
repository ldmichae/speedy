import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/ride_stats.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/core/tour.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:indoor_cycling/ui/elevation_service.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/tour_controller.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/in_memory_json_store.dart';

// Each stage is ~1.1 km north; stage n starts where n-1 ended.
SavedRoute stage(String name, double lat0, {ElevationProfile? ele}) => SavedRoute(
    name,
    [LatLng(lat0, 0), LatLng(lat0 + 0.01, 0)],
    [LatLng(lat0, 0), LatLng(lat0 + 0.01, 0)],
    elevation: ele);

/// Climbs [rise] metres over ~1.1 km starting at [start] metres.
ElevationProfile ele(double start, double rise) => ElevationProfile.fromSamples(
    [for (var i = 0; i <= 22; i++) i * 50.0],
    [for (var i = 0; i <= 22; i++) start + rise * i / 22]);

class FakeSource extends ElevationSource {
  int calls = 0;
  Object? failWith;
  @override
  Future<List<double>> elevations(List<LatLng> p) async {
    calls++;
    if (failWith != null) throw failWith!;
    return [for (var i = 0; i < p.length; i++) 10.0 + i];
  }
}

final meters = StateProvider<double>((ref) => 0);

void main() {
  test('a tour reads as one course across its stages', () {
    final t = Tour('t', 'T', [
      stage('S1', 0, ele: ele(0, 55)),
      stage('S2', 0.01, ele: ele(55, 0)),
      stage('S3', 0.02),
    ]);
    final one = t.stage(0).lengthMeters;
    expect(t.lengthMeters, closeTo(one * 3, 5));
    expect(t.stageAt(0), 0);
    expect(t.stageAt(one + 10), 1);
    expect(t.stageAt(1e9), 2);
    expect(t.stageStart(1), closeTo(one, 1e-6));
    expect(t.positionAt(one + 10).latitude, closeTo(0.01 + 10 / 111195, 1e-4));
    expect(t.gradeAt(100), closeTo(55 / one * 100, 0.6)); // inside stage 1
    // 50 m before the boundary the 150 m window reaches into flat stage 2
    expect(t.gradeAt(one - 50)!, lessThan(t.gradeAt(100)!));
    expect(t.gradeAt(2 * one + 100), isNull); // stage 3 has no elevation
    expect(t.gradeAt(2 * one - 50), isNull); // the window reaches into it
    expect(t.stagesWithElevation, 2);
  });

  test('json round-trips, bad data is rejected, edits keep "done" aligned', () {
    final t = Tour('t', 'T', [stage('a', 0), stage('b', 0.01), stage('c', 0.02)],
        completed: {0, 2});
    final back = Tour.fromJson(jsonDecode(jsonEncode(t.toJson())))!;
    expect(back.stageCount, 3);
    expect(back.completed, {0, 2});
    expect(Tour.fromJson({'v': 9}), isNull);
    expect(Tour.fromJson('x'), isNull);
    expect(t.withoutStage(0).completed, {1}); // old stage 2 is now 1
    expect(t.withCompleted(1).completed, {0, 1, 2});
  });

  test('simplifyPath drops straight-line detail but keeps the shape and ends', () {
    final straight = [for (var i = 0; i <= 100; i++) LatLng(i * 0.0001, 0)];
    expect(simplifyPath(straight), [straight.first, straight.last]);
    final ell = [
      for (var i = 0; i <= 50; i++) LatLng(i * 0.0001, 0),
      for (var i = 1; i <= 50; i++) LatLng(0.005, i * 0.0001),
    ];
    final s = simplifyPath(ell);
    expect(s.length, 3);
    expect(s[1], const LatLng(0.005, 0));
    final big = [for (var i = 0; i < 50000; i++) LatLng(i * 1e-6, (i % 7) * 1e-7)];
    expect(simplifyPath(big).length, lessThan(big.length)); // no stack overflow
  });

  group('the tour controllers', () {
    late InMemoryJsonStore store;
    late FakeSource source;

    ProviderContainer make() {
      store = InMemoryJsonStore();
      source = FakeSource();
      final c = ProviderContainer(overrides: [
        tourStoreProvider.overrideWithValue(store),
        elevationSourceProvider.overrideWithValue(source),
        liveRideStatsProvider.overrideWith((ref) => RideStats(
            duration: Duration.zero,
            distanceMeters: ref.watch(meters),
            avgPower: null,
            kcal: null)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final tour =
        Tour('t1', 'T', [stage('S1', 0), stage('S2', 0.01), stage('S3', 0.02)]);

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

    /// A recorder update, as the ride timer delivers once a second.
    Future<void> tick(ProviderContainer c) async {
      c.read(recorderProvider.notifier).pause();
      c.read(recorderProvider.notifier).resume();
      await settle();
    }

    test('tours persist and delete', () async {
      final c = make();
      await c.read(toursProvider.future);
      await c.read(toursProvider.notifier).upsert(tour);
      expect(store.rides.keys, ['t1']);
      c.invalidate(toursProvider);
      expect((await c.read(toursProvider.future)).single.name, 'T');
      await c.read(toursProvider.notifier).delete('t1');
      expect(store.rides, isEmpty);
    });

    test('elevation loads only when asked, once per stage, and is saved', () async {
      final c = make();
      await c.read(toursProvider.future);
      await c.read(toursProvider.notifier).upsert(tour);
      expect(source.calls, 0); // saving a tour costs nothing

      final loader = c.read(tourElevationProvider.notifier);
      await loader.load('t1', 1);
      expect(source.calls, 1);
      final t = c.read(toursProvider).value!.single;
      expect(t.stage(1).elevation, isNotNull);
      expect(t.stage(0).elevation, isNull);
      expect(c.read(tourElevationProvider), isEmpty);
      expect(store.rides['t1'], contains('"ele"'));

      await loader.load('t1', 1); // already there
      expect(source.calls, 1);
      await loader.loadAll('t1');
      expect(source.calls, 3); // only the two missing stages
    });

    test('a failure stays failed; a rate limit blocks every lookup', () async {
      final c = make();
      await c.read(toursProvider.future);
      await c.read(toursProvider.notifier).upsert(tour);
      final loader = c.read(tourElevationProvider.notifier);

      source.failWith = Exception('offline');
      await loader.load('t1', 0);
      expect(c.read(tourElevationProvider)[stageKey('t1', 0)]!.message, isNotNull);

      source.failWith = ElevationRateLimited(const Duration(seconds: 90));
      await loader.load('t1', 1);
      expect(source.calls, 2);
      expect(c.read(tourElevationProvider)[stageKey('t1', 1)]!.message,
          contains('2 min'));

      await loader.load('t1', 2); // blocked: no request at all
      expect(source.calls, 2);
      expect(c.read(tourElevationProvider)[stageKey('t1', 2)]!.message,
          contains('busy'));
    });

    test('riding prefetches this stage, then the next from 70%, and ticks stages off',
        () async {
      final c = make();
      await c.read(toursProvider.future);
      await c.read(toursProvider.notifier).upsert(tour);
      final t0 = c.read(toursProvider).value!.single;
      final one = t0.stage(0).lengthMeters;

      c.read(rideSessionProvider.notifier).startRoute(t0, simulate: true);
      await settle();
      expect(source.calls, 1); // stage 1 itself
      expect(c.read(toursProvider).value!.single.stage(0).elevation, isNotNull);
      // simulation rides on even though later stages have no elevation yet
      expect(c.read(trainerControllerProvider).gradePercent, isNotNull);

      c.read(meters.notifier).state = one * 0.5;
      await tick(c);
      expect(source.calls, 1); // not yet

      c.read(meters.notifier).state = one * 0.75;
      await tick(c);
      expect(source.calls, 2); // stage 2, once
      c.read(meters.notifier).state = one * 0.8;
      await tick(c);
      expect(source.calls, 2);

      c.read(meters.notifier).state = one + 50;
      await tick(c);
      expect(c.read(toursProvider).value!.single.completed, contains(0));
      c.read(rideSessionProvider.notifier).stopRoute();
      c.read(recorderProvider.notifier).discard();
    });

    test('starting at stage 3 begins there and does not tick earlier stages',
        () async {
      final c = make();
      await c.read(toursProvider.future);
      await c.read(toursProvider.notifier).upsert(tour);
      final t0 = c.read(toursProvider).value!.single;
      c.read(rideSessionProvider.notifier).startRoute(t0, stage: 2);
      final p = c.read(routeProgressProvider)!;
      expect(p.stage, 2);
      expect(p.meters, closeTo(t0.stageStart(2), 1e-6));
      await settle();
      expect(c.read(toursProvider).value!.single.completed, isEmpty);
      c.read(recorderProvider.notifier).discard();
    });

    test('a ride stopped mid-stage is picked up there next time', () async {
      final c = make();
      await c.read(toursProvider.future);
      await c.read(toursProvider.notifier).upsert(tour);
      Tour now() => c.read(toursProvider).value!.single;
      final session = c.read(rideSessionProvider.notifier);
      final at = now().stageStart(1) + 300;

      session.startRoute(now(), stage: 1);
      c.read(meters.notifier).state = 300;
      await tick(c);
      c.read(recorderProvider.notifier).discard(); // ends the ride
      await settle();
      expect(now().resumeAt, closeTo(at, 1e-6));
      expect(now().resumeStage, 1);
      expect(store.rides['t1'], contains('"at"'));

      // a separate ride, starting where the last one stopped
      c.read(meters.notifier).state = 0;
      session.startRoute(now(), stage: 1, at: now().resumeAt);
      expect(c.read(routeProgressProvider)!.meters, closeTo(at, 1e-6));
      session.stopRoute(); // went nowhere: the point is kept
      await settle();
      expect(now().resumeAt, closeTo(at, 1e-6));

      session.startRoute(now(), stage: 1, at: now().resumeAt);
      c.read(meters.notifier).state = 1e6; // to the stage's finish
      await tick(c);
      session.stopRoute();
      await settle();
      expect(now().resumeAt, isNull);
      expect(now().completed, contains(1));
      c.read(recorderProvider.notifier).discard();
    });
  });

  test('the resume point survives storage and elevation, not a length edit',
      () {
    final t = Tour('t', 'T', [stage('a', 0), stage('b', 0.01)]).withResume(500);
    expect(Tour.fromJson(t.toJson())!.resumeAt, 500);
    expect(Tour.fromJson({...t.toJson(), 'at': 1e9})!.resumeAt, isNull);
    final same = t.stage(0).withElevation(ElevationProfile.fromSamples(
        [0, t.stage(0).lengthMeters], [0, 10]));
    expect(t.withStage(0, same).resumeAt, 500);
    const a = LatLng(0, 0), b = LatLng(0.03, 0);
    expect(t.withStage(0, SavedRoute('long', [a, b], [a, b])).resumeAt, isNull);
  });

  test('RouteProgress reports the stage you are in', () {
    final t = Tour('t', 'T', [stage('a', 0), stage('b', 0.01)]);
    final m = t.stageStart(1) + 100;
    final p = RouteProgress(t, m, t.positionAt(m));
    expect(p.stage, 1);
    expect(p.stageRemaining, closeTo(t.stage(1).lengthMeters - 100, 1e-6));
  });
}
