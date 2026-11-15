import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/in_memory_json_store.dart';

// ~111 m per 0.001 degree of latitude.
final route = SavedRoute('R', const [LatLng(0, 0), LatLng(0.002, 0)],
    const [LatLng(0, 0), LatLng(0.001, 0), LatLng(0.002, 0)]);

class FakeSnapper implements RouteSnapper {
  RoadProfile? lastProfile;
  bool fail = false;
  @override
  Future<List<LatLng>> snap(LatLng a, LatLng b,
      {RoadProfile profile = RoadProfile.car}) async {
    lastProfile = profile;
    if (fail) throw Exception('down');
    return [a, const LatLng(0.0005, 0), b];
  }
}

void main() {
  roadProfileTests();
  test('length and positionAt interpolate and clamp', () {
    expect(route.lengthMeters, closeTo(222, 2));
    expect(route.positionAt(-5), route.path.first);
    expect(route.positionAt(1e9), route.path.last);
    expect(route.positionAt(route.lengthMeters / 2).latitude,
        closeTo(0.001, 1e-5));
    expect(route.positionAt(route.lengthMeters / 4).latitude,
        closeTo(0.0005, 1e-5));
  });

  test('json round-trips and rejects junk', () {
    final back = SavedRoute.fromJson(route.toJson())!;
    expect(back.name, 'R');
    expect(back.path.length, 3);
    expect(
        SavedRoute.fromJson({
          'name': 'x',
          'wp': [],
          'path': [
            [0, 0]
          ]
        }),
        isNull);
    expect(
        SavedRoute.fromJson({
          'name': 'x',
          'wp': [],
          'path': [
            [95, 0],
            [0, 0]
          ]
        }),
        isNull);
    expect(SavedRoute.fromJson('nope'), isNull);
  });

  test('distance text', () {
    expect(routeDistanceText(850, UnitSystem.metric), '850 m');
    expect(routeDistanceText(12400, UnitSystem.metric), '12.4 km');
    expect(routeDistanceText(12400, UnitSystem.imperial), '7.71 mi');
    expect(routeDistanceText(100, UnitSystem.imperial), '328 ft');
    expect(elevationText(100, UnitSystem.imperial), '328 ft');
  });

  test('OSRM response parses (lon,lat order); bad ones throw', () {
    final pts = parseOsrmRoute(
        '{"code":"Ok","routes":[{"geometry":{"coordinates":[[13.1,52.2],[13.2,52.3]]}}]}');
    expect(pts.first, const LatLng(52.2, 13.1));
    expect(() => parseOsrmRoute('{"code":"NoRoute","routes":[]}'),
        throwsFormatException);
  });

  test('OsrmSnapper requests the road engine, spaced out', () async {
    final times = <DateTime>[];
    final urls = <Uri>[];
    final s = OsrmSnapper(
      gap: const Duration(milliseconds: 80),
      client: MockClient((req) async {
        times.add(DateTime.now());
        urls.add(req.url);
        return http.Response(
            '{"code":"Ok","routes":[{"geometry":{"coordinates":[[1,2],[3,4]]}}]}',
            200);
      }),
    );
    await Future.wait([
      s.snap(const LatLng(2, 1), const LatLng(4, 3)),
      s.snap(const LatLng(2, 1), const LatLng(4, 3)),
    ]);
    expect(urls.first.path, contains('routed-car'));
    expect(urls.first.path, contains('1.0,2.0;3.0,4.0'));
    expect(
        times[1].difference(times[0]).inMilliseconds, greaterThanOrEqualTo(70));
  });

  test('snapOrStraight falls back to a straight line', () async {
    final s = FakeSnapper();
    expect((await snapOrStraight(s, const LatLng(0, 0), const LatLng(1, 1))).$2,
        isTrue);
    s.fail = true;
    final (path, ok) =
        await snapOrStraight(s, const LatLng(0, 0), const LatLng(1, 1));
    expect(ok, isFalse);
    expect(path.length, 2);
  });

  test('routes persist', () async {
    SharedPreferences.setMockInitialValues({});
    final store = InMemoryJsonStore();
    ProviderContainer open() {
      final c = ProviderContainer(
          overrides: [routesStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      return c;
    }

    open().read(routesProvider.notifier).add(route);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final c2 = open();
    c2.read(routesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(routesProvider).single.name, 'R');
  });

  test('routes saved in preferences move to the store once', () async {
    SharedPreferences.setMockInitialValues(
        {'routes': jsonEncode([route.toJson()])});
    final store = InMemoryJsonStore();
    final c = ProviderContainer(
        overrides: [routesStoreProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    c.read(routesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(routesProvider).single.name, 'R');
    expect(store.rides, hasLength(1));
    expect((await SharedPreferences.getInstance()).getString('routes'), isNull);
  });

  test('riding starts recording, begins at the start, ends with the ride', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(rideSessionProvider.notifier).startRoute(route);
    expect(c.read(recorderProvider).status, RecStatus.recording);
    final p = c.read(routeProgressProvider)!;
    expect(p.meters, 0);
    expect(p.position, route.path.first);
    expect(p.finished, isFalse);

    c.read(recorderProvider.notifier).discard();
    expect(c.read(routeRunProvider), isNull);
    expect(c.read(routeProgressProvider), isNull);
  });
}

void roadProfileTests() {
  test('segments use any road (car engine) unless the bike engine is asked for',
      () async {
    final urls = <Uri>[];
    final s = OsrmSnapper(
      gap: const Duration(milliseconds: 1),
      client: MockClient((req) async {
        urls.add(req.url);
        return http.Response(
            '{"code":"Ok","routes":[{"geometry":{"coordinates":[[1,2],[3,4]]}}]}',
            200);
      }),
    );
    await s.snap(const LatLng(2, 1), const LatLng(4, 3));
    await s.snap(const LatLng(2, 1), const LatLng(4, 3),
        profile: RoadProfile.bike);
    expect(urls[0].path, contains('routed-car'));
    expect(urls[1].path, contains('routed-bike'));
    expect(
        RoadProfile.values.map((p) => p.label), ['Any road', 'Bike-friendly']);
  });

  test('snapOrStraight passes the profile through', () async {
    final s = FakeSnapper();
    await snapOrStraight(s, const LatLng(0, 0), const LatLng(1, 1),
        profile: RoadProfile.bike);
    expect(s.lastProfile, RoadProfile.bike);
    await snapOrStraight(s, const LatLng(0, 0), const LatLng(1, 1));
    expect(s.lastProfile, RoadProfile.car);
  });

  test('the road choice defaults to any road and is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(roadProfileProvider), RoadProfile.car);
    c.read(roadProfileProvider.notifier).set(RoadProfile.bike);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(roadProfileProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(roadProfileProvider), RoadProfile.bike);
  });
}
