import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_stats.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/core/tour.dart';
import 'package:indoor_cycling/ui/elevation_chart.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:indoor_cycling/ui/elevation_service.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/route_map.dart';
import 'package:indoor_cycling/ui/route_tile.dart';
import 'package:indoor_cycling/ui/tour_controller.dart';
import 'package:indoor_cycling/ui/tour_screen.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/in_memory_json_store.dart';

class _Blank extends TileProvider {
  static final _png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  @override
  ImageProvider getImage(TileCoordinates c, TileLayer o) => MemoryImage(_png);
}

class _Hills extends ElevationSource {
  int calls = 0;
  @override
  Future<List<double>> elevations(List<LatLng> p) async {
    calls++;
    return [for (var i = 0; i < p.length; i++) 100.0 + i * 0.5];
  }
}

SavedRoute stage(String n, double lat) => SavedRoute(
    n, [LatLng(lat, 0), LatLng(lat + 0.02, 0)], [LatLng(lat, 0), LatLng(lat + 0.02, 0)]);

void main() {
  final tour = Tour('t1', 'Alps', [stage('Day 1', 0), stage('Day 2', 0.02)]);

  Future<_Hills> open(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = InMemoryJsonStore()
      ..rides['t1'] = jsonEncode(tour.toJson());
    final src = _Hills();
    await t.pumpWidget(ProviderScope(
      overrides: [
        tourStoreProvider.overrideWithValue(store),
        elevationSourceProvider.overrideWithValue(src),
        tileProviderProvider.overrideWithValue(_Blank()),
      ],
      child: MaterialApp(home: home),
    ));
    await t.pumpAndSettle();
    return src;
  }

  testWidgets('the list shows tours; a stage loads elevation only on request',
      (t) async {
    final src = await open(t, const ToursScreen());
    expect(find.text('Alps'), findsOneWidget);
    expect(find.textContaining('2 stages'), findsOneWidget);

    await t.tap(find.text('Alps'));
    await t.pumpAndSettle();
    expect(src.calls, 0); // opening a tour fetches nothing
    expect(find.text('Load elevation'), findsNWidgets(2));
    expect(find.textContaining('0/2 with elevation'), findsOneWidget);
    expect(find.byType(ElevationChart), findsNothing);

    await t.tap(find.text('Load elevation').first);
    await t.pumpAndSettle();
    expect(src.calls, 1);
    expect(find.text('Load elevation'), findsOneWidget); // only stage 2 is left
    expect(find.textContaining('1/2 with elevation'), findsOneWidget);
    expect(find.byType(ElevationChart), findsOneWidget);
  });

  testWidgets('"Load elevation for all stages" does the rest, one after another',
      (t) async {
    final src = await open(t, const TourScreen(tourId: 't1'));
    await t.tap(find.text('Load elevation for all stages'));
    await t.pumpAndSettle();
    expect(src.calls, 2);
    expect(find.textContaining('2/2 with elevation'), findsOneWidget);
    expect(find.text('Load elevation'), findsNothing);
  });

  testWidgets('the map tile shows the stage, distance left and the whole tour left',
      (t) async {
    await open(t, const Scaffold(body: SizedBox(width: 600, height: 500, child: RouteMapTile())));
    final c = ProviderScope.containerOf(t.element(find.byType(RouteMapTile)));
    await c.read(toursProvider.future);
    c.read(rideSessionProvider.notifier).startRoute(c.read(toursProvider).value!.single, stage: 1);
    await t.pump();
    final text = RouteMapTile.label(c.read(routeProgressProvider)!, UnitSystem.metric);
    expect(text, startsWith('Stage 2 of Alps'));
    expect(text, contains('to go'));
    // the stage you start on is prefetched at once, so its grade is already known
    expect(text, contains('%'));
    expect(text, isNot(contains('no elevation yet')));
    c.read(rideSessionProvider.notifier).stopRoute();
  });

  test('a tour ride ends with its stage, then rides on into the next if asked',
      () async {
    final dist = StateProvider<double>((_) => 0);
    final c = ProviderContainer(overrides: [
      tourStoreProvider.overrideWithValue(
          InMemoryJsonStore()..rides['t1'] = jsonEncode(tour.toJson())),
      elevationSourceProvider.overrideWithValue(_Hills()),
      liveRideStatsProvider.overrideWith((ref) => RideStats(
          duration: Duration.zero,
          distanceMeters: ref.watch(dist),
          avgPower: null,
          kcal: null)),
    ]);
    addTearDown(c.dispose);
    c.listen(nextStageProvider, (_, __) {});
    await c.read(toursProvider.future);
    final day1 = tour.stage(0).lengthMeters;
    c.read(rideSessionProvider.notifier).startRoute(tour);
    expect(c.read(nextStageProvider), isNull);

    c.read(dist.notifier).state = day1 + 50; // past the line, still riding
    expect(c.read(routeProgressProvider)!.finished, isTrue);
    expect(c.read(nextStageProvider), 1);

    c.read(rideSessionProvider.notifier).continueTour();
    final p = c.read(routeProgressProvider)!;
    expect(p.stage, 1);
    expect(p.meters, closeTo(day1, 0.001)); // the 50 m ridden on are not skipped
    expect(c.read(nextStageProvider), isNull);

    c.read(dist.notifier).state = 1e6;
    expect(RouteMapTile.label(c.read(routeProgressProvider)!, UnitSystem.metric),
        'Stage 2 done');
    expect(c.read(nextStageProvider), isNull); // no stage 3 to offer
  });
}
