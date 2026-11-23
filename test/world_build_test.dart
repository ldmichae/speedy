import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/course.dart';
import 'package:indoor_cycling/core/land_cover.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/world_build.dart';
import 'package:indoor_cycling/core/world_path.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // The app runs these on another isolate: everything they are sent and
  // send back has to cross, which only shows when it is actually sent.
  final drag = WorldPath.of(courseById('long-drag-v1')!.route);

  test('the road is planned on another isolate', () async {
    final pieces = await compute(planRoad, drag);
    expect(
        pieces.length, (drag.points.length - 1 + roadPiece - 1) ~/ roadPiece);
    for (final p in pieces) {
      final a = p.asphalt;
      expect(a.positions.length % 3, 0);
      expect(a.normals!.length, a.positions.length);
      expect(a.indices.length % 3, 0);
      expect(a.indices.reduce((x, y) => x > y ? x : y),
          lessThan(a.positions.length ~/ 3));
      expect(p.paint, isNotNull);
    }
  });

  test('the ground is planned on another isolate, with its land cover',
      () async {
    // A real-looking place: a wood and a house beside the road, on flat
    // terrain at the road's height.
    LatLng at(double x, double z) => drag.latLngOf(x, z);
    List<LatLng> box(double x0, double z0, double x1, double z1) =>
        [at(x0, z0), at(x1, z0), at(x1, z1), at(x0, z1), at(x0, z0)];
    final cover = LandCover([
      CoverArea('wood', Cover.forest, box(0, 20, 400, 300)),
    ], [
      Building('house', box(100, -40, 112, -30), 7),
    ]);
    final terrain = HeightGrid(-900, -900, groundCell, groundPosts,
        Float64List(groundPosts * groundPosts));
    final plan = await compute(planGround,
        (path: drag, cx: 0.0, cz: 0.0, terrain: terrain, cover: cover));
    expect(plan.tiles, hasLength(36)); // 6 x 6 tiles of 15 cells
    final tile = plan.tiles.first;
    expect(tile.colors!.length, tile.positions.length ~/ 3 * 4);
    // Trees are thick in the wood (400 m x 280 m) and sparse elsewhere.
    final inWood = plan.trees
        .where((t) => t.x > 0 && t.x < 400 && t.z > 20 && t.z < 300)
        .length;
    final woodDensity = inWood / (400 * 280);
    final restDensity =
        (plan.trees.length - inWood) / (1800 * 1800 - 400 * 280);
    expect(woodDensity, greaterThan(restDensity * 10));
    expect(plan.buildings, hasLength(1));
  });

  test('a route the ground square does not reach still plans', () {
    final far = WorldPath.of(SavedRoute(
        'x',
        [const LatLng(0, 0), const LatLng(0, 0.001)],
        [const LatLng(0, 0), const LatLng(0, 0.001)]));
    final plan = planGround(
        (path: far, cx: 50000.0, cz: 0.0, terrain: null, cover: null));
    expect(plan.tiles, isNotEmpty);
    expect(plan.buildings, isEmpty);
  });
}
