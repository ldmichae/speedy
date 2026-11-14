import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/core/terrain_cache.dart';
import 'package:indoor_cycling/core/terrain_tiles.dart';
import 'package:latlong2/latlong.dart';

/// A tile whose height is 100 m + the pixel column (so it rises 1 m a pixel).
Uint8List rampTile() {
  final image = img.Image(width: 256, height: 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final v = (100 + x + 32768).toDouble();
      image.setPixelRgb(x, y, v ~/ 256, (v % 256).floor(), ((v - v.floor()) * 256).floor());
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

// ~30 km north-south at Berlin's longitude.
final route = SavedRoute('R', const [LatLng(52.4, 13.4), LatLng(52.67, 13.4)],
    const [LatLng(52.4, 13.4), LatLng(52.67, 13.4)]);

void main() {
  test('Terrarium heights decode', () {
    expect(terrariumHeight(128, 0, 0), 0);
    expect(terrariumHeight(129, 44, 128), closeTo(300.5, 1e-9));
    expect(terrariumHeight(127, 255, 0), closeTo(-1, 1e-9));
  });

  test('a point maps to the right zoom-12 tile', () {
    final (x, y) = tileCoords(const LatLng(52.52, 13.405), 12);
    expect((x.floor(), y.floor()), (2200, 1343));
  });

  test('decoding and bilinear sampling', () {
    final t = TerrainTile.fromPng(rampTile());
    expect(t.sample(10.5, 40.5), closeTo(110, 0.01)); // a pixel centre
    expect(t.sample(11.0, 40.5), closeTo(110.5, 0.01)); // halfway between two
    expect(t.sample(0, 0), closeTo(100, 0.01)); // clamps at the edge
    expect(() => TerrainTile.fromPng(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });

  test('one download per tile, then none: the cache keeps them', () async {
    var fetches = 0;
    final src = TerrainTileElevation(
      cache: MemoryTerrainCache(),
      maxDecoded: 1, // force re-reads from the cache, not memory
      fetch: (z, x, y) async {
        fetches++;
        return rampTile();
      },
    );
    final p1 = await src.profile(route);
    final first = fetches;
    expect(first, inInclusiveRange(4, 7)); // ~30 km of tiles, not ~600 points
    expect(p1.lengthMeters, closeTo(route.lengthMeters, 1));
    expect(p1.distances.length, greaterThan(500)); // dense: every 50 m

    await src.profile(route);
    expect(fetches, first);
  });

  test('a bad tile is not cached and surfaces as an error', () async {
    final cache = MemoryTerrainCache();
    final src = TerrainTileElevation(
        cache: cache, fetch: (z, x, y) async => Uint8List.fromList([0, 1, 2]));
    await expectLater(src.elevations([const LatLng(52.5, 13.4)]), throwsA(anything));
    expect(await cache.read('12_2200_1343'), isNull);
  });

  test('Composite falls back on failure but passes a rate limit on', () async {
    final good = _Fixed([1, 2]);
    final bad = _Failing(Exception('offline'));
    final limited = _Failing(ElevationRateLimited(const Duration(seconds: 30)));
    final pts = [const LatLng(0, 0), const LatLng(1, 1)];
    expect(await CompositeElevation(bad, good).elevations(pts), [1, 2]);
    expect(await CompositeElevation(good, bad).elevations(pts), [1, 2]);
    await expectLater(CompositeElevation(limited, good).elevations(pts),
        throwsA(isA<ElevationRateLimited>()));
  });
}

class _Fixed extends ElevationSource {
  _Fixed(this.v);
  final List<double> v;
  @override
  Future<List<double>> elevations(List<LatLng> p) async => v;
}

class _Failing extends ElevationSource {
  _Failing(this.e);
  final Object e;
  @override
  Future<List<double>> elevations(List<LatLng> p) async => throw e;
}
