import 'dart:typed_data';

import 'terrain_cache_stub.dart' if (dart.library.io) 'terrain_cache_io.dart'
    as impl;

/// Where downloaded terrain tiles (and the World view's land cover) are kept
/// so each is fetched once, ever.
abstract class TerrainCache {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

/// Disk on native platforms, in [folder] with files ending [extension];
/// memory only on web (which does not use tiles).
TerrainCache createTerrainCache(
        {String folder = 'terrain', String extension = 'png'}) =>
    impl.createCache(folder, extension);

/// For tests, and the fallback when the disk is unavailable.
class MemoryTerrainCache implements TerrainCache {
  final _m = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => _m[key] = bytes;
}
