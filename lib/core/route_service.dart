import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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
  Future<void> _gate = Future.value();

  /// Runs [f] after the previous request plus [gap], one at a time.
  Future<T> _throttled<T>(Future<T> Function() f) {
    final run = _gate.then((_) => f());
    _gate = run.then((_) => Future<void>.delayed(gap),
        onError: (_) => Future<void>.delayed(gap));
    return run;
  }

  @override
  Future<List<LatLng>> snap(LatLng from, LatLng to) => _throttled(() async {
        final url = Uri.parse('$_base/${from.longitude},${from.latitude};'
            '${to.longitude},${to.latitude}?overview=full&geometries=geojson');
        final r = await _client.get(url, headers: {
          if (!kIsWeb) 'User-Agent': _userAgent, // browsers set their own
        }).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
        return parseOsrmRoute(r.body);
      });
}
