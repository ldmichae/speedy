// Throwaway: shows the World view riding a made-up winding, hilly route with
// two ghosts, no trainer needed. flutter run -t tool/world_preview.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/ghost.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/ui/compete_controller.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/world_view.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final path = [
    for (var i = 0; i <= 400; i++)
      LatLng(46 + i * 0.0002, 7 + 0.004 * math.sin(i / 25)),
  ];
  final len = pathLength(path);
  final route = SavedRoute('Preview', [path.first, path.last], path)
      .withElevation(ElevationProfile.fromSamples([
    for (var m = 0.0; m <= len; m += 25) m
  ], [
    for (var m = 0.0; m <= len; m += 25) 400 + 40 * math.sin(m / 700)
  ]));
  final ghosts = [
    for (final (i, v) in [9.0, 11.0].indexed)
      Ghost(id: '$i', course: 'x', name: 'g$i', t: [0, len / v], d: [0, len]),
  ];
  final sw = Stopwatch()..start();
  double secs() => sw.elapsedMilliseconds / 1000;
  runApp(ProviderScope(
    overrides: [
      routeProgressProvider.overrideWith((ref) {
        final t = Timer(const Duration(milliseconds: 500), ref.invalidateSelf);
        ref.onDispose(t.cancel);
        final m = math.min(secs() * 10, len);
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
              gap: gapTo(g, elapsed: s, riderMeters: s * 10),
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
