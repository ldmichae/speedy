// Throwaway: shows the World view riding a made-up out-and-back route with
// two ghosts, pedalling at 90 rpm, no trainer needed. flutter run -t tool/world_preview.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/ghost.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/terrain_cache.dart';
import 'package:indoor_cycling/core/terrain_tiles.dart';
import 'package:indoor_cycling/ui/compete_controller.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/world_view.dart';
import 'package:latlong2/latlong.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Out and back along a winding road in the hills south of Siena, heights
  // from the real terrain tiles (made-up ones if they cannot be fetched).
  // Starts just before the turn, to show the way back on the same road.
  final out = [
    for (var i = 0; i <= 200; i++)
      LatLng(43.20 + i * 0.0002, 11.40 + 0.004 * math.sin(i / 25)),
  ];
  final path = [...out, ...out.reversed.skip(1)];
  final len = pathLength(path), start = len / 2 - 150;
  var route = SavedRoute('Preview', [path.first, path.last], path);
  final client = http.Client();
  try {
    route = route.withElevation(await TerrainTileElevation(
            fetch: httpTileFetcher(client), cache: createTerrainCache())
        .profile(route));
  } catch (_) {
    route = route.withElevation(ElevationProfile.fromSamples(
        [for (var m = 0.0; m <= len; m += 25) m],
        [for (var m = 0.0; m <= len; m += 25) 400 + 40 * math.sin(m / 700)]));
  }
  client.close();
  final ghosts = [
    for (final (i, v) in [9.0, 11.0].indexed)
      Ghost(
          id: '$i',
          course: 'x',
          name: 'g$i',
          t: [0, (len - start) / v],
          d: [start, len]),
  ];
  final sw = Stopwatch()..start();
  double secs() => sw.elapsedMilliseconds / 1000;
  runApp(ProviderScope(
    overrides: [
      riderCadenceProvider.overrideWithValue(90),
      routeProgressProvider.overrideWith((ref) {
        final t = Timer(const Duration(milliseconds: 500), ref.invalidateSelf);
        ref.onDispose(t.cancel);
        final m = math.min(start + secs() * 10, len);
        return RouteProgress(route, m, route.positionAt(m));
      }),
      raceStandingsProvider.overrideWith((ref) {
        final t = Timer(const Duration(milliseconds: 500), ref.invalidateSelf);
        ref.onDispose(t.cancel);
        final s = secs();
        return [
          for (final g in ghosts)
            (
              ghost: g,
              gap: gapTo(g, elapsed: s, riderMeters: start + s * 10),
              watts: null,
              bpm: null,
              meters: g.distanceAt(s),
            ),
        ];
      }),
    ],
    child: const MaterialApp(home: Scaffold(body: WorldFocus())),
  ));
}
