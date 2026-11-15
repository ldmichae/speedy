import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/elevation.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import '../core/terrain_cache.dart';
import '../core/terrain_tiles.dart';

/// Terrain tiles first (cheap, cached, dense) on native; Open-Meteo when the
/// tiles fail, and on web where a browser cannot read them. Overridable so
/// tests never touch the network.
final elevationSourceProvider = Provider<ElevationSource>((ref) {
  final meteo = OpenMeteoElevation();
  if (kIsWeb) return meteo;
  final client = http.Client();
  ref.onDispose(client.close);
  return CompositeElevation(
    TerrainTileElevation(
        fetch: httpTileFetcher(client), cache: createTerrainCache()),
    meteo,
  );
});

/// Every elevation lookup goes through here, so a rate limit hit by one
/// caller (saving a route) holds back the others (loading a tour stage).
final elevationServiceProvider = Provider<ElevationService>(
    (ref) => ElevationService(ref.watch(elevationSourceProvider)));

class ElevationService {
  ElevationService(this._source);
  final ElevationSource _source;
  DateTime? _blockedUntil;

  /// How long lookups are held back, or null when they are not.
  Duration? get blockedFor {
    final left = _blockedUntil?.difference(DateTime.now());
    return left != null && !left.isNegative ? left : null;
  }

  /// The profile for [route]. Throws [ElevationRateLimited] without asking
  /// the source while a rate limit is still running.
  Future<ElevationProfile> profile(SavedRoute route) async {
    final wait = blockedFor;
    if (wait != null) throw ElevationRateLimited(wait);
    try {
      return await _source.profile(route);
    } on ElevationRateLimited catch (e) {
      _blockedUntil = DateTime.now().add(e.retryAfter);
      rethrow;
    }
  }
}
