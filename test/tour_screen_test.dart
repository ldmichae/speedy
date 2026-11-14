import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/core/tour.dart';
import 'package:indoor_cycling/ui/elevation_chart.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/route_map.dart';
import 'package:indoor_cycling/ui/route_tile.dart';
import 'package:indoor_cycling/ui/tour_controller.dart';
import 'package:indoor_cycling/ui/tour_screen.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/in_memory_ride_history_store.dart';

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
    final store = InMemoryRideHistoryStore()
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
    c.read(routeRunProvider.notifier).start(c.read(toursProvider).value!.single, stage: 1);
    await t.pump();
    final text = RouteMapTile.label(c.read(routeProgressProvider)!, UnitSystem.metric);
    expect(text, startsWith('Stage 2/2'));
    expect(text, contains('to go'));
    expect(text, contains('left'));
    // the stage you start on is prefetched at once, so its grade is already known
    expect(text, contains('%'));
    expect(text, isNot(contains('no elevation yet')));
    c.read(routeRunProvider.notifier).stop();
  });
}
