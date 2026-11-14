import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ride_history_store.dart';

RideHistoryStore createStore({String dir = 'history'}) =>
    FileRideHistoryStore(dir);

/// One JSON file per ride under the app support folder's `history` directory.
class FileRideHistoryStore implements RideHistoryStore {
  FileRideHistoryStore([this.dirName = 'history']);
  final String dirName;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}$dirName')
        .create(recursive: true);
  }

  @override
  Future<void> save(String id, String json) async {
    final dir = await _dir();
    await File('${dir.path}${Platform.pathSeparator}$id.json')
        .writeAsString(json);
  }

  @override
  Future<void> delete(String id) async {
    final dir = await _dir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (await file.exists()) await file.delete();
  }

  // shortcut: reads every ride in full to build the list; add a small index
  // file if history grows past a few hundred rides.
  @override
  Future<List<String>> loadAll() async {
    final dir = await _dir();
    return [
      await for (final f in dir.list())
        if (f is File && f.path.endsWith('.json')) await f.readAsString()
    ];
  }
}
