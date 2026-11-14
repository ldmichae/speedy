import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'elevation.dart';
import 'route.dart';

/// Identifies this app to OSM, FOSSGIS and Open-Meteo, which block anonymous
/// or borrowed user agents. (Browsers send their own and ignore this.)
const appUserAgent =
    'indoor-cycling-app/0.1 (+https://github.com/ldmichae/speedy)';

/// Which roads a route may use. The router is the public FOSSGIS OSRM, which
/// runs one engine per profile: the car one allows motorways and tunnels but
/// not cycle paths or tracks; the bike one is the reverse.
enum RoadProfile {
  car('routed-car', 'Any road'),
  bike('routed-bike', 'Bike-friendly');

  const RoadProfile(this.service, this.label);
  final String service;
  final String label;
}

/// Finds the roads between two points. Throws if it cannot.
abstract class RouteSnapper {
  Future<List<LatLng>> snap(LatLng from, LatLng to,
      {RoadProfile profile = RoadProfile.car});
}

/// The road path between [a] and [b]; a straight line, and `false`, when the
/// snapper fails (offline, rate limited, no road found).
Future<(List<LatLng>, bool)> snapOrStraight(
    RouteSnapper snapper, LatLng a, LatLng b,
    {RoadProfile profile = RoadProfile.car}) async {
  try {
    return (await snapper.snap(a, b, profile: profile), true);
  } catch (_) {
    return ([a, b], false);
  }
}

/// Points of the first route in an OSRM `route` response (GeoJSON geometry).
/// Throws FormatException if there is none.
List<LatLng> parseOsrmRoute(String body) {
  final j = jsonDecode(body);
  if (j is! Map ||
      j['code'] != 'Ok' ||
      j['routes'] is! List ||
      (j['routes'] as List).isEmpty) {
    throw FormatException('No route: ${j is Map ? j['code'] : 'bad response'}');
  }
  final coords = (((j['routes'] as List).first as Map)['geometry']
      as Map)['coordinates'] as List;
  final pts = [
    for (final c in coords.cast<List>())
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  if (pts.length < 2) throw const FormatException('Route too short');
  return pts;
}

/// The public FOSSGIS OSRM server (car or bike engine). Its policy: at most one request per
/// second, an identifying user agent, visible attribution, no heavy use. A
/// keyed provider (GraphHopper etc.) would be another [RouteSnapper].
class OsrmSnapper implements RouteSnapper {
  OsrmSnapper({http.Client? client, this.gap = const Duration(seconds: 1)})
      : _client = client ?? http.Client();

  static String _base(RoadProfile p) =>
      'https://routing.openstreetmap.de/${p.service}/route/v1/driving';

  final http.Client _client;
  final Duration gap;
  late final _gate = _Gate(gap);

  @override
  Future<List<LatLng>> snap(LatLng from, LatLng to,
          {RoadProfile profile = RoadProfile.car}) =>
      _gate.run(() async {
        final url = Uri.parse('${_base(profile)}/${from.longitude},${from.latitude};'
            '${to.longitude},${to.latitude}?overview=full&geometries=geojson');
        final r = await _client.get(url, headers: {
          if (!kIsWeb) 'User-Agent': appUserAgent, // browsers set their own
        }).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200)
          throw http.ClientException('HTTP ${r.statusCode}');
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
  const ElevationSource();

  Future<List<double>> elevations(List<LatLng> points);

  /// How densely to sample a route (metres) and the most points one route may
  /// cost. API sources keep this small; tile sources do not need to.
  double get preferredStep => 100;
  int get maxPoints => 250;

  /// The whole route's profile. Sources may override to do it differently.
  Future<ElevationProfile> profile(SavedRoute route) async {
    final pts = samplePoints(route, step: preferredStep, maxPoints: maxPoints);
    final heights = await elevations([for (final p in pts) p.$2]);
    return ElevationProfile.fromSamples([for (final p in pts) p.$1], heights);
  }
}

/// Tries [primary]; if it fails for any reason except being rate limited,
/// asks [fallback]. (A rate limit is passed on: the fallback is a different
/// service and the caller should hear about the busy one.)
class CompositeElevation extends ElevationSource {
  const CompositeElevation(this.primary, this.fallback);
  final ElevationSource primary, fallback;

  @override
  Future<List<double>> elevations(List<LatLng> points) async {
    try {
      return await primary.elevations(points);
    } on ElevationRateLimited {
      rethrow;
    } catch (_) {
      return fallback.elevations(points);
    }
  }

  @override
  Future<ElevationProfile> profile(SavedRoute route) async {
    try {
      return await primary.profile(route);
    } on ElevationRateLimited {
      rethrow;
    } catch (_) {
      return fallback.profile(route);
    }
  }
}

/// The elevation service said to slow down. Try again in about
/// [retryAfter].
class ElevationRateLimited implements Exception {
  ElevationRateLimited(this.retryAfter);
  final Duration retryAfter;
  @override
  String toString() => 'Elevation service is rate limited; retry in '
      '${retryAfter.inSeconds} s';
}

/// Heights from Open-Meteo's free elevation API (Copernicus DEM, ~90 m;
/// free for non-commercial use). It bills one unit per coordinate against
/// 600 a minute (also ~5000 an hour, ~10000 a day), not one per request, so
/// this paces itself by the `X-RateLimit-*` headers on every reply and never
/// retries a 429: it stops and says so.
class OpenMeteoElevation extends ElevationSource {
  OpenMeteoElevation({
    http.Client? client,
    Duration gap = const Duration(milliseconds: 500),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _gate = _Gate(gap),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? Future<void>.delayed;

  final http.Client _client;
  final _Gate _gate;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  static const batch = 100;

  // From the last response: units left in this window, and when it resets.
  int? _remaining;
  DateTime? _resetAt;

  @override
  Future<List<double>> elevations(List<LatLng> points) async {
    final out = <double>[];
    for (var i = 0; i < points.length; i += batch) {
      final chunk = points.sublist(
          i, i + batch > points.length ? points.length : i + batch);
      out.addAll(await _gate.run(() => _fetch(chunk)));
    }
    return out;
  }

  /// Waits out the window if the last reply said this batch would not fit.
  Future<void> _pace(int cost) async {
    final left = _remaining, reset = _resetAt;
    if (left == null || reset == null || left >= cost) return;
    final wait = reset.difference(_now());
    if (wait > Duration.zero) await _sleep(wait + const Duration(seconds: 1));
    _remaining = null;
  }

  Future<List<double>> _fetch(List<LatLng> pts) async {
    await _pace(pts.length);
    final url = Uri.parse('https://api.open-meteo.com/v1/elevation'
        '?latitude=${pts.map((p) => p.latitude.toStringAsFixed(5)).join(',')}'
        '&longitude=${pts.map((p) => p.longitude.toStringAsFixed(5)).join(',')}');
    final r = await _client.get(url).timeout(const Duration(seconds: 20));
    _remaining = int.tryParse(
        r.headers['x-ratelimit-remaining']?.split('.').first ?? '');
    final reset = int.tryParse(r.headers['x-ratelimit-reset'] ?? '');
    _resetAt = reset == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(reset * 1000);
    if (r.statusCode == 429) {
      throw ElevationRateLimited(Duration(
          seconds: int.tryParse(r.headers['retry-after'] ?? '') ?? 60));
    }
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
/// The DEM is ~90 m, so 100 m steps lose nothing, and capping the count keeps
/// one route inside the elevation API's per-minute budget.
List<(double, LatLng)> samplePoints(SavedRoute route,
    {double step = 100, int maxPoints = 250}) {
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
Future<ElevationProfile> buildElevation(
        SavedRoute route, ElevationSource source) =>
    source.profile(route);
