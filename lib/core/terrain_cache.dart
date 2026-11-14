import 'dart:typed_data';

import 'terrain_cache_stub.dart' if (dart.library.io) 'terrain_cache_io.dart'
    as impl;

/// Where downloaded terrain tiles are kept so a tile is fetched once, ever.
abstract class TerrainCache {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

/// Disk on native platforms; memory only on web (which does not use tiles).
TerrainCache createTerrainCache() => impl.createCache();

/// For tests, and the fallback when the disk is unavailable.
class MemoryTerrainCache implements TerrainCache {
  final _m = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => _m[key] = bytes;
}
