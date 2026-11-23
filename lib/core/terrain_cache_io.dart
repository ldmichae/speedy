import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'terrain_cache.dart';

TerrainCache createCache(String folder, String extension) =>
    FileTerrainCache(folder, extension);

/// One file per key under the app support folder's [folder] directory.
/// Any disk problem is treated as a cache miss: the data is just fetched
/// again.
class FileTerrainCache implements TerrainCache {
  FileTerrainCache(this.folder, this.extension);

  final String folder, extension;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}$folder')
        .create(recursive: true);
  }

  Future<File> _file(String key) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$key.$extension');

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
