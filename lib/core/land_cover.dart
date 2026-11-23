import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'route_service.dart' show appUserAgent;
import 'terrain_cache.dart';

/// What covers the ground somewhere, as the World view draws it.
enum Cover {
  grass,
  forest,
  scrub,
  farmland,
  urban,
  water,
  wetland,
  sand,
  rock,
  snow
}

/// An OpenStreetMap area of one [cover]: an outer ring (holes ignored).
class CoverArea {
  CoverArea(this.id, this.cover, this.ring) : area = _area(ring);
  final String id;
  final Cover cover;
  final List<LatLng> ring;

  /// Square degrees, near enough to say which of two areas is smaller.
  final double area;

  static double _area(List<LatLng> r) {
    var s = 0.0;
    for (var i = 0, j = r.length - 1; i < r.length; j = i++) {
      s += (r[j].longitude * r[i].latitude) - (r[i].longitude * r[j].latitude);
    }
    return s.abs() / 2;
  }
}

/// A building footprint and how tall it is (metres).
class Building {
  Building(this.id, this.ring, this.height);
  final String id;
  final List<LatLng> ring;
  final double height;
}

/// The areas and buildings OpenStreetMap has for a patch of the world.
class LandCover {
  LandCover(this.areas, this.buildings);
  final List<CoverArea> areas;
  final List<Building> buildings;

  static final empty = LandCover(const [], const []);

  /// Several patches as one, each area and building once.
  static LandCover merge(Iterable<LandCover> parts) {
    final areas = <String, CoverArea>{};
    final buildings = <String, Building>{};
    for (final p in parts) {
      for (final a in p.areas) {
        areas[a.id] = a;
      }
      for (final b in p.buildings) {
        buildings[b.id] = b;
      }
    }
    return LandCover([...areas.values], [...buildings.values]);
  }
}

/// The [Cover] an OSM feature's [tags] describe, or null for none we draw.
Cover? coverOf(Map<String, dynamic> tags) {
  switch (tags['natural']) {
    case 'wood':
      return Cover.forest;
    case 'scrub' || 'heath':
      return Cover.scrub;
    case 'grassland' || 'fell':
      return Cover.grass;
    case 'water' || 'bay':
      return Cover.water;
    case 'wetland':
      return Cover.wetland;
    case 'sand' || 'beach' || 'dune':
      return Cover.sand;
    case 'bare_rock' || 'scree' || 'shingle' || 'rock':
      return Cover.rock;
    case 'glacier':
      return Cover.snow;
  }
  switch (tags['landuse']) {
    case 'forest':
      return Cover.forest;
    case 'farmland' || 'orchard' || 'vineyard' || 'allotments' || 'farmyard':
      return Cover.farmland;
    case 'meadow' || 'grass' || 'village_green' || 'recreation_ground':
      return Cover.grass;
    case 'residential' ||
          'commercial' ||
          'industrial' ||
          'retail' ||
          'construction' ||
          'railway' ||
          'garages':
      return Cover.urban;
    case 'reservoir' || 'basin':
      return Cover.water;
    case 'quarry':
      return Cover.rock;
  }
  switch (tags['leisure']) {
    case 'park' || 'golf_course' || 'pitch':
      return Cover.grass;
  }
  return null;
}

/// Metres tall: the `height` tag, else 3 m a storey, else by kind.
double buildingHeight(Map<String, dynamic> tags) {
  final h =
      double.tryParse('${tags['height'] ?? ''}'.replaceAll('m', '').trim());
  if (h != null && h > 0) return h;
  final levels = double.tryParse('${tags['building:levels'] ?? ''}');
  if (levels != null && levels > 0) return levels * 3 + 1;
  return switch (tags['building']) {
    'garage' || 'garages' || 'shed' || 'hut' || 'roof' || 'carport' => 3,
    'apartments' || 'office' || 'hotel' => 15,
    'church' || 'cathedral' => 18,
    _ => 7,
  };
}

/// Joins way pieces end to end into closed rings (an OSM multipolygon's
/// outer boundary is often drawn as several ways). Pieces that never close
/// are dropped.
List<List<LatLng>> stitchRings(List<List<LatLng>> pieces) {
  bool same(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-9 &&
      (a.longitude - b.longitude).abs() < 1e-9;
  final left = [
    for (final p in pieces)
      if (p.length >= 2) List.of(p)
  ];
  final rings = <List<LatLng>>[];
  while (left.isNotEmpty) {
    final ring = left.removeLast();
    var grew = true;
    while (!same(ring.first, ring.last) && grew) {
      grew = false;
      for (var i = 0; i < left.length; i++) {
        final p = left[i];
        if (same(ring.last, p.first)) {
          ring.addAll(p.skip(1));
        } else if (same(ring.last, p.last)) {
          ring.addAll(p.reversed.skip(1));
        } else {
          continue;
        }
        left.removeAt(i);
        grew = true;
        break;
      }
    }
    if (ring.length >= 4 && same(ring.first, ring.last)) rings.add(ring);
  }
  return rings;
}

/// The areas and buildings in an Overpass `out geom` JSON reply.
/// Throws FormatException if it is not one.
LandCover parseOverpass(String body) {
  final j = jsonDecode(body);
  if (j is! Map || j['elements'] is! List) {
    throw const FormatException('Not an Overpass reply');
  }
  List<LatLng> pts(Object? geometry) => [
        for (final g in (geometry as List? ?? const []).cast<Map>())
          LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble())
      ];
  final areas = <CoverArea>[];
  final buildings = <Building>[];
  for (final e in (j['elements'] as List).cast<Map>()) {
    final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final id = '${e['type']}/${e['id']}';
    if (e['type'] == 'way') {
      final ring = pts(e['geometry']);
      if (ring.length < 4 || ring.first != ring.last) continue; // not an area
      if (tags.containsKey('building')) {
        buildings.add(Building(id, ring, buildingHeight(tags)));
      } else if (coverOf(tags) case final c?) {
        areas.add(CoverArea(id, c, ring));
      }
    } else if (e['type'] == 'relation') {
      final c = coverOf(tags);
      if (c == null) continue;
      final outer = [
        for (final m in (e['members'] as List? ?? const []).cast<Map>())
          if (m['type'] == 'way' && m['role'] != 'inner') pts(m['geometry'])
      ];
      for (final (i, ring) in stitchRings(outer).indexed) {
        areas.add(CoverArea('$id#$i', c, ring));
      }
    }
  }
  return LandCover(areas, buildings);
}

/// Sends an Overpass QL [query]; returns the reply body. Throws if it cannot.
typedef OverpassFetcher = Future<String> Function(String query);

/// Public Overpass servers, main one first. They are often at capacity, so
/// a busy one passes the query to the next.
const overpassServers = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

/// The public Overpass API: a POST with an identifying user agent to each
/// of [servers] in turn until one answers. No retries beyond that (its
/// fair-use policy asks for no hammering; the cache means each patch is
/// asked for once, and a failed one again only on a later ground build).
OverpassFetcher httpOverpassFetcher(http.Client client,
        {List<String> servers = overpassServers}) =>
    (query) async {
      Object? last;
      for (final url in servers) {
        try {
          final r = await client.post(Uri.parse(url),
              headers: {'User-Agent': appUserAgent},
              body: {'data': query}).timeout(const Duration(seconds: 60));
          if (r.statusCode == 200) return r.body;
          last = http.ClientException('Overpass HTTP ${r.statusCode}');
        } catch (e) {
          last = e; // timed out or unreachable: the next server
        }
      }
      throw last ?? http.ClientException('No Overpass server');
    };

/// Land cover by grid cell of [cellDegrees], each fetched once and kept.
class LandCoverSource {
  LandCoverSource({required this.fetch, TerrainCache? cache})
      : _cache = cache ?? MemoryTerrainCache();

  final OverpassFetcher fetch;
  final TerrainCache _cache;

  static const cellDegrees = 0.02; // ~2 km

  /// Bump to fetch every cell again (after changing [query]).
  static const _version = 1;

  /// What to ask for in the box south, west, north, east.
  static String query(double s, double w, double n, double e) {
    final b = '($s,$w,$n,$e)';
    return '[out:json][timeout:60];('
        'way["landuse"]$b;relation["landuse"]["type"="multipolygon"]$b;'
        'way["natural"]$b;relation["natural"]["type"="multipolygon"]$b;'
        'way["leisure"~"^(park|golf_course|pitch)\$"]$b;'
        'way["building"]$b;'
        ');out geom;';
  }

  /// Everything in the cells the box south, west, north, east touches, one
  /// cell at a time. Throws if a cell cannot be had.
  Future<LandCover> around(double s, double w, double n, double e) async {
    int cell(double deg) => (deg / cellDegrees).floor();
    final parts = <LandCover>[];
    for (var i = cell(s); i <= cell(n); i++) {
      for (var k = cell(w); k <= cell(e); k++) {
        parts.add(await _cell(i, k));
      }
    }
    return LandCover.merge(parts);
  }

  /// The cell requests, one after another: Overpass gives each address two
  /// slots, and overlapping ground builds ask for the same cells (the second
  /// then finds them cached).
  Future<void> _queue = Future.value();

  Future<LandCover> _cell(int i, int k) {
    final next = _queue.then((_) => _load(i, k));
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<LandCover> _load(int i, int k) async {
    final key = 'v${_version}_${i}_$k';
    final hit = await _cache.read(key);
    if (hit != null) {
      try {
        return await compute(parseOverpass, utf8.decode(hit));
      } on FormatException {
        // A damaged file: fetch it again.
      }
    }
    final s = i * cellDegrees, w = k * cellDegrees;
    final body = await fetch(query(s, w, s + cellDegrees, w + cellDegrees));
    // Parsed off the UI thread: a town's reply is megabytes of JSON.
    final cover = await compute(parseOverpass, body); // validates first
    await _cache.write(key, Uint8List.fromList(utf8.encode(body)));
    return cover;
  }
}

/// Whether ([x], [y]) is inside the polygon [xs], [ys] (even-odd rule).
bool insideRing(double x, double y, List<double> xs, List<double> ys) {
  var inside = false;
  for (var i = 0, j = xs.length - 1; i < xs.length; j = i++) {
    if ((ys[i] > y) != (ys[j] > y) &&
        x < (xs[j] - xs[i]) * (y - ys[i]) / (ys[j] - ys[i]) + xs[i]) {
      inside = !inside;
    }
  }
  return inside;
}

/// Polygons in local metres with their bounding boxes, for quick "what is
/// here" lookups while building the ground.
class LocalShapes<T> {
  LocalShapes(this.items, this.xs, this.zs)
      : minX = [for (final x in xs) x.reduce(math.min)],
        maxX = [for (final x in xs) x.reduce(math.max)],
        minZ = [for (final z in zs) z.reduce(math.min)],
        maxZ = [for (final z in zs) z.reduce(math.max)];

  final List<T> items;
  final List<List<double>> xs, zs;
  final List<double> minX, maxX, minZ, maxZ;

  /// Indexes of the shapes containing ([x], [z]).
  Iterable<int> containing(double x, double z) sync* {
    for (var i = 0; i < items.length; i++) {
      if (x < minX[i] || x > maxX[i] || z < minZ[i] || z > maxZ[i]) continue;
      if (insideRing(x, z, xs[i], zs[i])) yield i;
    }
  }
}

/// The cover at ([x], [z]): the smallest area there (a park inside a town
/// is park), or [fallback] where OSM has none.
Cover coverAt(LocalShapes<CoverArea> areas, double x, double z,
    {Cover fallback = Cover.grass}) {
  CoverArea? best;
  for (final i in areas.containing(x, z)) {
    final a = areas.items[i];
    if (best == null || a.area < best.area) best = a;
  }
  return best?.cover ?? fallback;
}
