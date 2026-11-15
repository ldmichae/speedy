import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/plan.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/tour.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:latlong2/latlong.dart';

SavedRoute stage(double lat0, {ElevationProfile? ele}) => SavedRoute(
    's',
    [LatLng(lat0, 0), LatLng(lat0 + 0.01, 0)],
    [LatLng(lat0, 0), LatLng(lat0 + 0.01, 0)],
    elevation: ele);

// A steady 5% climb over the first stage's ~1.1 km.
final climb = ElevationProfile.fromSamples(
    [for (var i = 0; i <= 22; i++) i * 50.0],
    [for (var i = 0; i <= 22; i++) i * 2.5]);

void main() {
  group('tickPlan', () {
    final steps = const Plan('p', [
      PlanBlock([PlanStep(10, 150)]),
      PlanBlock([PlanStep(10, 200)]),
    ]).expand();
    PlanRun run() => PlanRun('p', steps, 100, 0);

    test('sends a step once, and again after being told it was not applied',
        () {
      var t = tickPlan(run(), recorderSeconds: 103, recording: true);
      expect(t.send, 150);
      expect(t.next!.elapsed, 3);
      t = tickPlan(run(), recorderSeconds: 104, recording: true, applied: 150);
      expect(t.send, isNull);
      t = tickPlan(run(), recorderSeconds: 112, recording: true, applied: 150);
      expect(t.send, 200);
    });

    test('sends nothing while paused', () {
      expect(tickPlan(run(), recorderSeconds: 103, recording: false).send,
          isNull);
    });

    test('ends after the last step', () {
      expect(tickPlan(run(), recorderSeconds: 125, recording: true).next,
          isNull);
    });
  });

  group('tickRoute', () {
    test('does nothing while paused', () {
      final r = RouteRun(stage(0, ele: climb), 0, simulate: true);
      expect(tickRoute(r, rideMeters: 100, recording: false, doneUpTo: 0),
          isNull);
    });

    test('a simulated route follows its grade, and is flat past the end', () {
      final r = RouteRun(stage(0, ele: climb), 0, simulate: true);
      final mid = tickRoute(r, rideMeters: 500, recording: true, doneUpTo: 0)!;
      expect(mid.grade, closeTo(5, 0.3));
      final end = tickRoute(r, rideMeters: 99999, recording: true, doneUpTo: 0)!;
      expect(end.grade, 0);
      expect(end.meters, r.course.lengthMeters);
    });

    test('an ERG route has no grade; riding starts at its origin', () {
      final r = RouteRun(stage(0, ele: climb), 400);
      final t = tickRoute(r, rideMeters: 500, recording: true, doneUpTo: 0)!;
      expect(t.grade, isNull);
      expect(t.meters, 100);
    });

    test('a tour reports each stage passed once', () {
      final tour = Tour('t', 'T', [stage(0), stage(0.01), stage(0.02)]);
      final r = RouteRun(tour, 0);
      final s1 = tout(r, tour.stageStart(1) + 10, 0);
      expect(s1.completed, [0]);
      expect(s1.doneUpTo, 1);
      final again = tout(r, tour.stageStart(1) + 20, s1.doneUpTo);
      expect(again.completed, isEmpty);
      final finish = tout(r, 99999, again.doneUpTo);
      expect(finish.completed, [1, 2]);
      expect(finish.prefetch, same(tour));
    });
  });
}

RouteTick tout(RouteRun r, double m, int done) =>
    tickRoute(r, rideMeters: m, recording: true, doneUpTo: done)!;
