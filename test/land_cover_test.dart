import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indoor_cycling/core/land_cover.dart';
import 'package:indoor_cycling/core/region_style.dart';
import 'package:indoor_cycling/core/terrain_cache.dart';

Map<String, num> _p(double lat, double lon) => {'lat': lat, 'lon': lon};

/// A square of side [d] degrees from (lat, lon), closed.
List<Map<String, num>> _square(double lat, double lon, double d) => [
      _p(lat, lon),
      _p(lat, lon + d),
      _p(lat + d, lon + d),
      _p(lat + d, lon),
      _p(lat, lon),
    ];

final _reply = jsonEncode({
  'elements': [
    {
      'type': 'way',
      'id': 1,
      'tags': {'landuse': 'residential'},
      'geometry': _square(45, 7, 0.01),
    },
    {
      'type': 'way',
      'id': 2,
      'tags': {'leisure': 'park'},
      'geometry': _square(45.002, 7.002, 0.002),
    },
    {
      'type': 'way',
      'id': 3,
      'tags': {'building': 'house', 'building:levels': '3'},
      'geometry': _square(45.006, 7.006, 0.0001),
    },
    {
      'type': 'way', // a road: not an area, not drawn
      'id': 4,
      'tags': {'highway': 'primary'},
      'geometry': [_p(45, 7), _p(45.1, 7.1)],
    },
    {
      // A forest whose outline is two ways, the second drawn backwards.
      'type': 'relation',
      'id': 5,
      'tags': {'type': 'multipolygon', 'natural': 'wood'},
      'members': [
        {
          'type': 'way',
          'role': 'outer',
          'geometry': [_p(46, 7), _p(46, 7.01), _p(46.01, 7.01)],
        },
        {
          'type': 'way',
          'role': 'outer',
          'geometry': [_p(46, 7), _p(46.01, 7), _p(46.01, 7.01)],
        },
      ],
    },
  ],
});

void main() {
  test('reads areas, buildings and stitched multipolygons', () {
    final c = parseOverpass(_reply);
    expect({
      for (final a in c.areas) a.id: a.cover
    }, {
      'way/1': Cover.urban,
      'way/2': Cover.grass,
      'relation/5#0': Cover.forest,
    });
    final forest = c.areas.firstWhere((a) => a.id == 'relation/5#0');
    expect(forest.ring.length, 5);
    expect(forest.ring.first, forest.ring.last);
    expect(c.buildings.single.height, 10); // 3 storeys
  });

  test('a park in a town is park; nowhere mapped is the fallback', () {
    final c = parseOverpass(_reply);
    // Degrees as the "local" plane is enough for the lookup.
    final shapes = LocalShapes(c.areas, [
      for (final a in c.areas) [for (final p in a.ring) p.longitude]
    ], [
      for (final a in c.areas) [for (final p in a.ring) p.latitude]
    ]);
    expect(coverAt(shapes, 7.003, 45.003), Cover.grass);
    expect(coverAt(shapes, 7.008, 45.008), Cover.urban);
    expect(coverAt(shapes, 8, 50, fallback: Cover.farmland), Cover.farmland);
  });

  test('building heights from tags', () {
    expect(buildingHeight({'building': 'yes', 'height': '12 m'}), 12);
    expect(buildingHeight({'building': 'shed'}), 3);
    expect(buildingHeight({'building': 'yes'}), 7);
  });

  test('rejects a reply that is not from Overpass', () {
    expect(() => parseOverpass('{"error":"busy"}'), throwsFormatException);
  });

  test('fetches each cell once, then reads it from the cache', () async {
    final asked = <String>[];
    final cache = MemoryTerrainCache();
    final source = LandCoverSource(
        fetch: (q) async {
          asked.add(q);
          return _reply;
        },
        cache: cache);
    // A box inside one 0.02 degree cell, then one spanning four.
    await source.around(45.001, 7.001, 45.01, 7.01);
    expect(asked, hasLength(1));
    final c = await source.around(45.01, 7.01, 45.03, 7.03);
    expect(asked, hasLength(4)); // the first cell came from the cache
    expect(c.areas.where((a) => a.id == 'way/1'), hasLength(1)); // merged
  });

  test('a damaged cache file is fetched again', () async {
    final cache = MemoryTerrainCache();
    await cache.write('v1_2250_350', Uint8List.fromList(utf8.encode('junk')));
    var asked = 0;
    final source = LandCoverSource(
        fetch: (_) async {
          asked++;
          return _reply;
        },
        cache: cache);
    await source.around(45.001, 7.001, 45.01, 7.01);
    expect(asked, 1);
  });

  group('RegionStyle', () {
    test('tree lines fall towards the poles', () {
      expect(RegionStyle(0).treeline, 3800);
      expect(RegionStyle(46).treeline, closeTo(1960, 1));
      expect(RegionStyle(-46).treeline, RegionStyle(46).treeline);
      expect(RegionStyle(46).treeChance(2500), 0);
      expect(RegionStyle(46).treeChance(500), 1);
    });

    test('palms in the tropics, conifers in the north and up high', () {
      final tropics = RegionStyle(10), alps = RegionStyle(46);
      final kinds = {for (var r = 0.0; r < 1; r += 0.05) tropics.tree(100, r)};
      expect(kinds, contains(TreeKind.palm));
      expect(kinds, isNot(contains(TreeKind.conifer)));
      expect(RegionStyle(65).tree(100, 0.9), TreeKind.conifer);
      expect(alps.tree(1800, 0.9), TreeKind.conifer); // near the tree line
      expect(alps.tree(200, 0.9), TreeKind.broadleaf);
    });

    test('snow above the snow line; terracotta roofs in the south', () {
      final alps = RegionStyle(46);
      expect(alps.ground(Cover.grass, 3000, 0).x, greaterThan(0.8));
      expect(alps.ground(Cover.grass, 300, 0).x, lessThan(0.2));
      expect(RegionStyle(43).building(0.5).roof,
          RegionStyle(36).building(0.1).roof);
      expect(RegionStyle(55).warm, isFalse);
    });
  });

  test('a busy Overpass server passes the query to the next', () async {
    final hit = <String>[];
    final fetch = httpOverpassFetcher(MockClient((r) async {
      hit.add(r.url.host);
      return r.url.host == 'a'
          ? http.Response('busy', 504)
          : http.Response(_reply, 200);
    }), servers: ['https://a/i', 'https://b/i']);
    expect(await fetch('q'), _reply);
    expect(hit, ['a', 'b']);
  });

  test('two builds asking at once fetch each cell once', () async {
    var asked = 0;
    final source = LandCoverSource(fetch: (_) async {
      asked++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _reply;
    });
    await Future.wait([
      source.around(45.001, 7.001, 45.01, 7.01),
      source.around(45.001, 7.001, 45.01, 7.01),
    ]);
    expect(asked, 1);
  });
}
