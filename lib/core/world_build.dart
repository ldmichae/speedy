import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math.dart';

import 'land_cover.dart';
import 'region_style.dart';
import 'world_path.dart';

// The World view's meshes, worked out as plain arrays by pure functions so
// they can run on a background isolate: the UI thread only uploads them.

/// Half the road's width, metres.
const halfRoad = 3.0;

/// The ground square around the rider: half its side, the spacing of its
/// height posts, and the posts per mesh tile (~300 m, small enough that the
/// engine can fit its depth range around the camera).
const groundHalf = 900.0, groundCell = 20.0, groundTile = 15;

/// Height posts along one side of the ground square.
const groundPosts = (2 * groundHalf) ~/ groundCell + 1;

/// Road samples per road mesh piece (~400 m).
const roadPiece = 40;

/// Most buildings drawn in a ground square, nearest the middle first.
const maxBuildings = 6000;

/// One mesh's vertex arrays: three floats a position and a normal (null:
/// the engine makes them), four a colour (null: white), three indices a
/// triangle.
typedef MeshArrays = ({
  Float32List positions,
  Float32List? normals,
  Float32List? colors,
  Uint32List indices,
});

/// Collects vertices and triangles, then hands them over as [MeshArrays].
class _Arrays {
  _Arrays({this.normals = false, this.colors = false});
  final bool normals, colors;
  final _p = <double>[], _n = <double>[], _c = <double>[];
  final _i = <int>[];
  Vector3 _normal = Vector3(0, 1, 0);
  Vector3 _color = Vector3.all(1);

  int get count => _p.length ~/ 3;
  bool get isEmpty => _i.isEmpty;

  void normal(Vector3 n) => _normal = n;
  void color(Vector3 c) => _color = c;

  int add(Vector3 p) {
    _p.addAll([p.x, p.y, p.z]);
    if (normals) _n.addAll([_normal.x, _normal.y, _normal.z]);
    if (colors) _c.addAll([_color.x, _color.y, _color.z, 1]);
    return count - 1;
  }

  void tri(int a, int b, int c) => _i.addAll([a, b, c]);

  /// Four vertices [a] [b] [c] [d] as two triangles: a-b one edge, c-d the
  /// matching points opposite.
  void quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d) {
    final i = add(a);
    add(b);
    add(c);
    add(d);
    tri(i, i + 1, i + 2);
    tri(i + 2, i + 1, i + 3);
  }

  MeshArrays done() => (
        positions: Float32List.fromList(_p),
        normals: normals ? Float32List.fromList(_n) : null,
        colors: colors ? Float32List.fromList(_c) : null,
        indices: Uint32List.fromList(_i),
      );
}

/// One stretch of road: its asphalt, its centre line (null if none), and
/// the road points at its ends (to hide it when it is off the ground).
typedef RoadPiece = ({
  MeshArrays asphalt,
  MeshArrays? paint,
  Vector3 from,
  Vector3 to,
});

/// The whole road of [path], in pieces of [roadPiece] samples. Stretches the
/// course rides a second time (an out-and-back) are drawn once.
List<RoadPiece> planRoad(WorldPath path) {
  final pts = path.points;
  final last = pts.length - 1;
  // A stretch with both ends on road already drawn is that road again.
  bool repeat(int i) =>
      i + 1 < pts.length && path.retraced[i] && path.retraced[i + 1];
  final up = Vector3(0, 1, 0), down = Vector3(0, -2, 0);
  const dash = 3.0, every = 10.0, half = 0.07;
  return [
    for (var from = 0; from < last; from += roadPiece)
      () {
        final to = math.min(from + roadPiece, last);
        final asphalt = _Arrays(normals: true);
        for (var i = from; i < to; i++) {
          if (repeat(i)) continue;
          final r0 =
              WorldPath.rightOf(path.heading(i * path.step, span: path.step));
          final r1 = WorldPath.rightOf(
              path.heading((i + 1) * path.step, span: path.step));
          final l0 = pts[i] - r0 * halfRoad, l1 = pts[i + 1] - r1 * halfRoad;
          final x0 = pts[i] + r0 * halfRoad, x1 = pts[i + 1] + r1 * halfRoad;
          asphalt
            ..normal(up)
            ..quad(l0, l1, x0, x1)
            // Sides down into the ground, so the road never floats.
            ..normal(-r0)
            ..quad(l0 + down, l1 + down, l0, l1)
            ..normal(r0)
            ..quad(x0, x1, x0 + down, x1 + down);
        }
        final paint = _Arrays(normals: true)..normal(up);
        final end = math.min(to * path.step, path.length - dash);
        for (var m = (from * path.step / every).ceil() * every;
            m < end;
            m += every) {
          if (repeat((m / path.step).floor())) continue;
          final r = WorldPath.rightOf(path.heading(m)) * half;
          final a = path.at(m), b = path.at(m + dash);
          paint.quad(a - r, b - r, a + r, b + r);
        }
        return (
          asphalt: asphalt.done(),
          paint: paint.isEmpty ? null : paint.done(),
          from: pts[from],
          to: pts[to],
        );
      }(),
  ];
}

/// A tree to plant: its kind, where its foot is, its size (1 = usual) and a
/// random 0..1 for its shade of green.
typedef PlannedTree = ({
  TreeKind kind,
  double x,
  double y,
  double z,
  double size,
  double r,
});

/// Everything on one ground square: its tiles, its trees, and its buildings
/// (in pieces like the tiles).
typedef GroundPlan = ({
  List<MeshArrays> tiles,
  List<PlannedTree> trees,
  List<MeshArrays> buildings,
});

/// [items]' outlines in [path]'s local metres, keeping those that reach the
/// square of half-size [half] around ([cx], [cz]).
LocalShapes<T> localShapes<T>(WorldPath path, Iterable<T> items,
    List<LatLng> Function(T) ring, double cx, double cz, double half) {
  final kept = <T>[];
  final xs = <List<double>>[], zs = <List<double>>[];
  for (final item in items) {
    final x = <double>[], z = <double>[];
    for (final p in ring(item)) {
      final (px, pz) = path.localOf(p);
      x.add(px);
      z.add(pz);
    }
    if (x.reduce(math.max) < cx - half || x.reduce(math.min) > cx + half) {
      continue;
    }
    if (z.reduce(math.max) < cz - half || z.reduce(math.min) > cz + half) {
      continue;
    }
    kept.add(item);
    xs.add(x);
    zs.add(z);
  }
  return LocalShapes(kept, xs, zs);
}

/// Trees per 12.5 m cell on each cover (scrub grows bushes).
double treeDensity(Cover c) => switch (c) {
      Cover.forest => 0.9,
      Cover.scrub => 0.5,
      Cover.urban => 0.06,
      Cover.grass || Cover.wetland => 0.05,
      Cover.farmland => 0.01,
      Cover.water || Cover.sand || Cover.rock || Cover.snow => 0,
    };

/// A random 0..1 that is the same everywhere within one [size] m square.
double patchRandom(double x, double z, double size) =>
    math.Random((x / size).floor() * 73856093 ^ (z / size).floor() * 19349663)
        .nextDouble();

/// The ground square around ([cx], [cz]) on [path]'s course. With [terrain]
/// it is a real place, styled for its latitude; [cover] says where its
/// forests, fields, towns and water are. Takes a record so it can be sent
/// to an isolate whole.
GroundPlan planGround(
    ({
      WorldPath path,
      double cx,
      double cz,
      HeightGrid? terrain,
      LandCover? cover,
    }) job) {
  final (:path, :cx, :cz, :terrain, :cover) = job;
  final road = path.near(cx, cz, groundHalf + 150);
  final style = terrain == null
      ? RegionStyle.temperate
      : RegionStyle(path.origin.latitude);
  final areas = localShapes(path, cover?.areas ?? const <CoverArea>[],
      (a) => a.ring, cx, cz, groundHalf);
  final houses = localShapes(path, cover?.buildings ?? const <Building>[],
      (b) => b.ring, cx, cz, groundHalf);
  Cover coverHere(double x, double z) => coverAt(areas, x, z);
  double above(double y) => y + path.baseHeight; // metres above the sea

  const n = groundPosts;
  final pos = <Vector3>[], col = <Vector3>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final x = cx - groundHalf + c * groundCell;
      final z = cz - groundHalf + r * groundCell;
      final g = groundAt(x, z, road, terrain: terrain);
      final shade = 0.8 + 0.2 * math.sin(x / 37) * math.cos(z / 29);
      col.add(g.road < 4
          ? Vector3(0.18, 0.15, 0.10) // verge
          : style.ground(coverHere(x, z), above(g.y), patchRandom(x, z, 90)) *
              shade);
      pos.add(Vector3(x, g.y, z));
    }
  }
  final tiles = <MeshArrays>[];
  for (var r0 = 0; r0 < n - 1; r0 += groundTile) {
    for (var c0 = 0; c0 < n - 1; c0 += groundTile) {
      final w = math.min(groundTile, n - 1 - c0) + 1;
      final h = math.min(groundTile, n - 1 - r0) + 1;
      final b = _Arrays(colors: true);
      for (var r = r0; r < r0 + h; r++) {
        for (var c = c0; c < c0 + w; c++) {
          b
            ..color(col[r * n + c])
            ..add(pos[r * n + c]);
        }
      }
      // Wound so the surface faces up (see flutter_scene's terrain recipe).
      for (var r = 0; r < h - 1; r++) {
        for (var c = 0; c < w - 1; c++) {
          final v00 = r * w + c, v10 = v00 + 1, v01 = v00 + w, v11 = v01 + 1;
          b
            ..tri(v00, v01, v10)
            ..tri(v10, v01, v11);
        }
      }
      tiles.add(b.done());
    }
  }

  final trees = [
    for (final t in treesAround(cx, cz, groundHalf, road, terrain: terrain,
        chance: (x, z) {
      final density = cover == null ? 0.09 : treeDensity(coverHere(x, z));
      if (density == 0) return 0;
      if (houses.containing(x, z).isNotEmpty) return 0; // not indoors
      return density * style.treeChance(above(terrain?.at(x, z) ?? 0));
    }))
      (
        kind: cover != null && coverHere(t.x, t.z) == Cover.scrub
            ? TreeKind.bush
            : style.tree(above(t.y), t.r),
        x: t.x,
        y: t.y,
        z: t.z,
        size: t.size,
        r: t.r,
      ),
  ];

  return (
    tiles: tiles,
    trees: trees,
    buildings: _buildings(houses, road, terrain, style, cx, cz),
  );
}

/// [houses] as walls and roofs, one mesh per ground tile's square. Ones the
/// road would run through (OSM and the route line disagreeing by a few
/// metres) are left out.
///
/// shortcut: flat roofs fanned from the middle (a courtyard building gets a
/// lid), and only the [maxBuildings] nearest ([cx], [cz]). Revisit for
/// cities if riders want skylines.
List<MeshArrays> _buildings(LocalShapes<Building> houses, List<Vector3> road,
    HeightGrid? terrain, RegionStyle style, double cx, double cz) {
  final order = [for (var i = 0; i < houses.items.length; i++) i];
  if (order.length > maxBuildings) {
    double d(int i) =>
        (houses.xs[i].first - cx).abs() + (houses.zs[i].first - cz).abs();
    order.sort((a, b) => d(a).compareTo(d(b)));
    order.length = maxBuildings;
  }
  const piece = groundTile * groundCell;
  final pieces = <(int, int), _Arrays>{};
  for (final i in order) {
    final xs = houses.xs[i], zs = houses.zs[i];
    final m = xs.length - 1; // the ring repeats its first point
    if (m < 3) continue;
    var base = double.infinity;
    var clear = true;
    for (var k = 0; k < m; k++) {
      final g = groundAt(xs[k], zs[k], road, terrain: terrain);
      if (g.road < halfRoad + 1) clear = false;
      base = math.min(base, g.y);
    }
    if (!clear) continue;
    final top = base + houses.items[i].height;
    final look = style.building(patchRandom(xs[0], zs[0], 1));
    var mx = 0.0, mz = 0.0;
    for (var k = 0; k < m; k++) {
      mx += xs[k] / m;
      mz += zs[k] / m;
    }
    final b = pieces.putIfAbsent(((mx / piece).floor(), (mz / piece).floor()),
        () => _Arrays(colors: true));
    b.color(look.wall);
    for (var k = 0; k < m; k++) {
      b.quad(
          Vector3(xs[k], base, zs[k]),
          Vector3(xs[k], top, zs[k]),
          Vector3(xs[k + 1], base, zs[k + 1]),
          Vector3(xs[k + 1], top, zs[k + 1]));
    }
    b.color(look.roof);
    final hub = b.add(Vector3(mx, top, mz));
    for (var k = 0; k < m; k++) {
      final j = b.add(Vector3(xs[k], top, zs[k]));
      b
        ..add(Vector3(xs[k + 1], top, zs[k + 1]))
        ..tri(hub, j, j + 1);
    }
  }
  return [
    for (final b in pieces.values)
      if (!b.isEmpty) b.done()
  ];
}
