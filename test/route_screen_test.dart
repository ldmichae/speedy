import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_stats.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/ui/elevation_chart.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/route_map.dart';
import 'package:indoor_cycling/ui/route_screen.dart';
import 'package:indoor_cycling/ui/route_tile.dart';
import 'package:latlong2/latlong.dart';

class _Blank extends TileProvider {
  static final _png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  @override
  ImageProvider getImage(TileCoordinates c, TileLayer o) => MemoryImage(_png);
}

class _Straight implements RouteSnapper {
  @override
  Future<List<LatLng>> snap(LatLng a, LatLng b,
          {RoadProfile profile = RoadProfile.car}) async =>
      [a, b];
}

class _Hills extends ElevationSource {
  bool fail = false;
  @override
  Future<List<double>> elevations(List<LatLng> p) async => fail
      ? throw Exception("down")
      : [for (var i = 0; i < p.length; i++) i * 1.0];
}

final _route = SavedRoute('R', const [LatLng(0, 0), LatLng(0.002, 0)],
    const [LatLng(0, 0), LatLng(0.001, 0), LatLng(0.002, 0)]);

final _meters = StateProvider<double>((ref) => 0);

void main() {
  elevationEditorTests();
  editRouteTests();
  Widget app(Widget child) => ProviderScope(
        overrides: [
          tileProviderProvider.overrideWithValue(_Blank()),
          routeSnapperProvider.overrideWithValue(_Straight()),
          liveRideStatsProvider.overrideWith((ref) => RideStats(
              duration: Duration.zero,
              distanceMeters: ref.watch(_meters),
              avgPower: null,
              kcal: null)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 500, height: 700, child: child))),
      );

  testWidgets('tapping the map adds points, snaps and enables Save', (t) async {
    t.view.physicalSize = const Size(500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        tileProviderProvider.overrideWithValue(_Blank()),
        routeSnapperProvider.overrideWithValue(_Straight()),
      ],
      child: const MaterialApp(home: RouteEditor()),
    ));
    final map = find.byType(FlutterMap);
    await t.tapAt(t.getCenter(map));
    await t.pump();
    await t.tapAt(t.getCenter(map) + const Offset(60, 40));
    await t.pump();
    await t.pump();
    expect(find.text('Snapping…'), findsNothing);
    expect(find.textContaining('km'), findsOneWidget);
    expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, 'Save')).onPressed,
        isNotNull);
    expect(find.text('2'), findsOneWidget); // second marker
  });

  testWidgets('the tile shows the dot moving along the route, then finished',
      (t) async {
    await t.pumpWidget(app(const RouteMapTile()));
    expect(find.text('No route selected'), findsOneWidget);

    final c = ProviderScope.containerOf(t.element(find.byType(RouteMapTile)));
    c.read(routeRunProvider.notifier).start(_route);
    await t.pump();
    LatLng dot() =>
        t.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.point;
    expect(dot().latitude, closeTo(0, 1e-9));

    c.read(_meters.notifier).state = _route.lengthMeters / 2;
    await t.pump();
    expect(dot().latitude, closeTo(0.001, 1e-5));

    c.read(_meters.notifier).state = 1e6;
    await t.pump();
    expect(dot().latitude, closeTo(0.002, 1e-9));
    expect(find.textContaining('finished'), findsOneWidget);

    c.read(recorderProvider.notifier).discard();
    await t.pump();
    expect(find.text('No route selected'), findsOneWidget);
  });
}

void elevationEditorTests() {
  testWidgets(
      'the editor shows elevation on request and saves it with the route',
      (t) async {
    t.view.physicalSize = const Size(500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SavedRoute? saved;
    await t.pumpWidget(ProviderScope(
      overrides: [
        tileProviderProvider.overrideWithValue(_Blank()),
        routeSnapperProvider.overrideWithValue(_Straight()),
        elevationSourceProvider.overrideWithValue(_Hills()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => saved = await Navigator.of(context).push(
                  MaterialPageRoute<SavedRoute>(
                      builder: (_) => const RouteEditor())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final map = find.byType(FlutterMap);
    await t.tapAt(t.getCenter(map));
    await t.pump();
    await t.tapAt(t.getCenter(map) + const Offset(0, -100));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Show elevation'));
    await t.pumpAndSettle();
    expect(find.byType(ElevationChart), findsOneWidget);
    expect(find.textContaining('steepest'), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(saved?.elevation, isNotNull);
  });
}

void editRouteTests() {
  testWidgets(
      'editing a route starts from its points; a rename keeps path and elevation',
      (t) async {
    t.view.physicalSize = const Size(500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final a = const LatLng(0, 0),
        b = const LatLng(0, 0.01),
        mid = const LatLng(0, 0.005);
    final original = SavedRoute('Loop', [a, b], [a, mid, b],
        elevation: ElevationProfile.fromSamples(
            [0.0, 500.0, 1000.0], [1.0, 2.0, 3.0]));
    SavedRoute? saved;
    await t.pumpWidget(ProviderScope(
      overrides: [
        tileProviderProvider.overrideWithValue(_Blank()),
        routeSnapperProvider.overrideWithValue(_Straight()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => saved = await Navigator.of(context).push(
                  MaterialPageRoute<SavedRoute>(
                      builder: (_) => RouteEditor(
                          initialName: original.name, initial: original))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('2'), findsOneWidget); // both waypoints are placed

    await t.enterText(find.byType(TextField).first, 'Renamed');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(saved?.name, 'Renamed');
    expect(saved?.waypoints, original.waypoints);
    expect(saved?.elevation, isNotNull);
    expect(saved?.path.first, a);
    expect(saved?.path.last, b);
  });
}
