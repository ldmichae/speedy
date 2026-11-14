import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'elevation.dart';
import 'route.dart';

/// Finds the roads between two points. Throws if it cannot.
abstract class RouteSnapper {
  Future<List<LatLng>> snap(LatLng from, LatLng to);
}

/// The road path between [a] and [b]; a straight line, and `false`, when the
/// snapper fails (offline, rate limited, no road found).
Future<(List<LatLng>, bool)> snapOrStraight(
    RouteSnapper snapper, LatLng a, LatLng b) async {
  try {
    return (await snapper.snap(a, b), true);
  } catch (_) {
    return ([a, b], false);
  }
}

/// Points of the first route in an OSRM `route` response (GeoJSON geometry).
/// Throws FormatException if there is none.
List<LatLng> parseOsrmRoute(String body) {
  final j = jsonDecode(body);
  if (j is! Map || j['code'] != 'Ok' || j['routes'] is! List || (j['routes'] as List).isEmpty) {
    throw FormatException('No route: ${j is Map ? j['code'] : 'bad response'}');
  }
  final coords = (((j['routes'] as List).first as Map)['geometry'] as Map)['coordinates'] as List;
  final pts = [
    for (final c in coords.cast<List>())
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  if (pts.length < 2) throw const FormatException('Route too short');
  return pts;
}

/// The public FOSSGIS OSRM bike server. Its policy: at most one request per
/// second, an identifying user agent, visible attribution, no heavy use. A
/// keyed provider (GraphHopper etc.) would be another [RouteSnapper].
class OsrmSnapper implements RouteSnapper {
  OsrmSnapper({http.Client? client, this.gap = const Duration(seconds: 1)})
      : _client = client ?? http.Client();

  static const _base = 'https://routing.openstreetmap.de/routed-bike/route/v1/driving';
  static const _userAgent = 'indoor-cycling-app/0.1 (personal training app)';

  final http.Client _client;
  final Duration gap;
  late final _gate = _Gate(gap);

  @override
  Future<List<LatLng>> snap(LatLng from, LatLng to) => _gate.run(() async {
        final url = Uri.parse('$_base/${from.longitude},${from.latitude};'
            '${to.longitude},${to.latitude}?overview=full&geometries=geojson');
        final r = await _client.get(url, headers: {
          if (!kIsWeb) 'User-Agent': _userAgent, // browsers set their own
        }).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
        return parseOsrmRoute(r.body);
      });
}

/// Runs one async job at a time, [gap] apart: public servers ask for it.
class _Gate {
  _Gate(this.gap);
  final Duration gap;
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() f) {
    final r = _tail.then((_) => f());
    _tail = r.then((_) => Future<void>.delayed(gap),
        onError: (_) => Future<void>.delayed(gap));
    return r;
  }
}

/// Heights for points on the map. Throws if it cannot.
abstract class ElevationSource {
  Future<List<double>> elevations(List<LatLng> points);
}

/// Heights from Open-Meteo's free elevation API (Copernicus DEM, ~90 m;
/// free for non-commercial use, up to 100 points a request).
class OpenMeteoElevation implements ElevationSource {
  OpenMeteoElevation({http.Client? client, Duration gap = const Duration(milliseconds: 300)})
      : _client = client ?? http.Client(),
        _gate = _Gate(gap);

  final http.Client _client;
  final _Gate _gate;
  static const batch = 100;

  @override
  Future<List<double>> elevations(List<LatLng> points) async {
    final out = <double>[];
    for (var i = 0; i < points.length; i += batch) {
      final chunk = points.sublist(i, i + batch > points.length ? points.length : i + batch);
      out.addAll(await _gate.run(() => _fetch(chunk)));
    }
    return out;
  }

  Future<List<double>> _fetch(List<LatLng> pts) async {
    final url = Uri.parse('https://api.open-meteo.com/v1/elevation'
        '?latitude=${pts.map((p) => p.latitude.toStringAsFixed(5)).join(',')}'
        '&longitude=${pts.map((p) => p.longitude.toStringAsFixed(5)).join(',')}');
    final r = await _client.get(url).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
    final j = jsonDecode(r.body);
    final e = j is Map ? j['elevation'] : null;
    if (e is! List || e.length != pts.length || e.any((x) => x is! num)) {
      throw const FormatException('Bad elevation response');
    }
    return [for (final x in e) (x as num).toDouble()];
  }
}

/// Points every [step] metres along [route] (always including the end),
/// widening the step so a very long route stays under [maxPoints].
List<(double, LatLng)> samplePoints(SavedRoute route,
    {double step = 50, int maxPoints = 1500}) {
  final len = route.lengthMeters;
  final s = step < len / maxPoints ? len / maxPoints : step;
  final out = <(double, LatLng)>[];
  if (len <= 0) return [(0, route.path.first), (0, route.path.last)];
  for (var d = 0.0; d < len; d += s) {
    out.add((d, route.positionAt(d)));
  }
  out.add((len, route.path.last));
  return out;
}

/// Looks up the route's elevation profile.
Future<ElevationProfile> buildElevation(SavedRoute route, ElevationSource source) async {
  final pts = samplePoints(route);
  final heights = await source.elevations([for (final p in pts) p.$2]);
  return ElevationProfile.fromSamples([for (final p in pts) p.$1], heights);
}
