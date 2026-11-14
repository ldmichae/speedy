import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'terrain_cache.dart';

TerrainCache createCache() => FileTerrainCache();

/// One PNG per tile under the app support folder's `terrain` directory.
/// Any disk problem is treated as a cache miss: the tile is just fetched again.
class FileTerrainCache implements TerrainCache {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}terrain')
        .create(recursive: true);
  }

  Future<File> _file(String key) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$key.png');

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final f = await _file(key);
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    try {
      await (await _file(key)).writeAsBytes(bytes);
    } catch (_) {}
  }
}
