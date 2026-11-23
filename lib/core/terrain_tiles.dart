import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

import 'route_service.dart';
import 'terrain_cache.dart';

/// Terrarium encoding: metres = R*256 + G + B/256 - 32768.
double terrariumHeight(int r, int g, int b) => r * 256 + g + b / 256 - 32768;

const terrainZoom = 12;

/// Slippy-map tile coordinates (fractional) of a point at [zoom].
(double, double) tileCoords(LatLng p, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final lat = p.latitudeInRad;
  final x = (p.longitude + 180) / 360 * n;
  final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n;
  return (x, y);
}

/// One decoded 256x256 tile of heights in metres.
class TerrainTile {
  TerrainTile(this.heights);
  final Float32List heights;
  static const size = 256;

  factory TerrainTile.fromPng(Uint8List bytes) {
    final image = img.decodePng(bytes);
    if (image == null || image.width != size || image.height != size) {
      throw const FormatException('Not a 256x256 terrain tile');
    }
    final h = Float32List(size * size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final px = image.getPixel(x, y);
        h[y * size + x] =
            terrariumHeight(px.r.toInt(), px.g.toInt(), px.b.toInt());
      }
    }
    return TerrainTile(h);
  }

  /// Bilinear height at fractional pixel position ([px], [py]), clamped to
  /// the tile (an edge point can be off by about a pixel, ~25-40 m).
  double sample(double px, double py) {
    final x = (px - 0.5).clamp(0.0, size - 1.0);
    final y = (py - 0.5).clamp(0.0, size - 1.0);
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, size - 1), y1 = math.min(y0 + 1, size - 1);
    final fx = x - x0, fy = y - y0;
    double h(int xx, int yy) => heights[yy * size + xx];
    final top = h(x0, y0) * (1 - fx) + h(x1, y0) * fx;
    final bot = h(x0, y1) * (1 - fx) + h(x1, y1) * fx;
    return top * (1 - fy) + bot * fy;
  }
}

/// Fetches the PNG bytes of one tile. Throws if it cannot.
typedef TileFetcher = Future<Uint8List> Function(int z, int x, int y);

const _tileUrl = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium';

/// The public AWS Terrain Tiles bucket. Plain GET, identifying user agent,
/// no retries; the cache means each tile is downloaded once.
TileFetcher httpTileFetcher(http.Client client) => (z, x, y) async {
      final r = await client.get(Uri.parse('$_tileUrl/$z/$x/$y.png'), headers: {
        'User-Agent': appUserAgent
      }).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200)
        throw http.ClientException('HTTP ${r.statusCode}');
      return r.bodyBytes;
    };

/// Heights read from terrain tiles instead of an API. The cost is one tile
/// download (~100 KB, ~7-10 km across at zoom 12) per area, not per point,
/// and tiles are cached on disk forever, so sampling can be dense and a
/// ridden tour needs no network again. Native platforms only: the bucket sends
/// no CORS headers, so a browser cannot read the pixels.
class TerrainTileElevation extends ElevationSource {
  TerrainTileElevation(
      {required this.fetch, TerrainCache? cache, this.maxDecoded = 16})
      : _cache = cache ?? MemoryTerrainCache();

  final TileFetcher fetch;
  final TerrainCache _cache;
  final int maxDecoded;
  final _decoded = <String, TerrainTile>{}; // insertion order = LRU order

  /// Tile downloads are limited to this many at once.
  static const parallelDownloads = 2;

  @override
  double get preferredStep => 50;
  @override
  int get maxPoints => 100000;

  Future<TerrainTile> _tile(int z, int x, int y) async {
    final key = '${z}_${x}_$y';
    final hit = _decoded.remove(key);
    if (hit != null) return _decoded[key] = hit;
    var bytes = await _cache.read(key);
    final fresh = bytes == null;
    bytes ??= await fetch(z, x, y);
    // Off the UI thread: decoding a tile takes long enough to drop frames.
    final tile = await compute(_decodeTile, bytes); // validates before caching
    if (fresh) await _cache.write(key, bytes);
    _decoded[key] = tile;
    while (_decoded.length > maxDecoded) {
      _decoded.remove(_decoded.keys.first);
    }
    return tile;
  }

  @override
  Future<List<double>> elevations(List<LatLng> points) async {
    final coords = [for (final p in points) tileCoords(p, terrainZoom)];
    final needed = <(int, int)>{
      for (final (x, y) in coords) (x.floor(), y.floor())
    }.toList();
    // Points run in order, so tiles are needed in order: load a few at a
    // time, then read every point that falls in them.
    final out = List<double>.filled(points.length, 0);
    for (var i = 0; i < needed.length; i += parallelDownloads) {
      final batch =
          needed.sublist(i, math.min(i + parallelDownloads, needed.length));
      final tiles = await Future.wait(
          [for (final (x, y) in batch) _tile(terrainZoom, x, y)]);
      for (var k = 0; k < points.length; k++) {
        final (cx, cy) = coords[k];
        for (var b = 0; b < batch.length; b++) {
          if (cx.floor() == batch[b].$1 && cy.floor() == batch[b].$2) {
            out[k] = tiles[b].sample((cx - cx.floor()) * TerrainTile.size,
                (cy - cy.floor()) * TerrainTile.size);
          }
        }
      }
    }
    return out;
  }
}

TerrainTile _decodeTile(Uint8List bytes) => TerrainTile.fromPng(bytes);
