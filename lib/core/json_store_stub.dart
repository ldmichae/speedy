import 'package:shared_preferences/shared_preferences.dart';

import 'json_store.dart';

JsonStore createStore(String dir, {bool webSupported = true}) =>
    webSupported ? _PrefsStore(dir) : _UnsupportedStore();

class _UnsupportedStore implements JsonStore {
  @override
  Future<void> save(String id, String json) async =>
      throw UnsupportedError('Ride history is not supported on web yet.');

  @override
  Future<void> delete(String id) async =>
      throw UnsupportedError('Ride history is not supported on web yet.');

  @override
  Future<List<String>> loadAll() async => const [];
}

/// Web has no files, so other stores (tours) live in shared preferences.
/// shortcut: browsers cap this at a few MB in total; tours of several
/// hundred km can hit it. Upgrade to IndexedDB if that bites.
class _PrefsStore implements JsonStore {
  _PrefsStore(this.name);
  final String name;
  String get _index => '$name.index';
  String _key(String id) => '$name.$id';

  @override
  Future<void> save(String id, String json) async {
    final p = await SharedPreferences.getInstance();
    final ids = {...?p.getStringList(_index), id};
    if (!await p.setString(_key(id), json)) {
      throw StateError('Could not store $name (browser storage full?)');
    }
    await p.setStringList(_index, ids.toList());
  }

  @override
  Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(id));
    await p.setStringList(_index, [...?p.getStringList(_index)]..remove(id));
  }

  @override
  Future<List<String>> loadAll() async {
    final p = await SharedPreferences.getInstance();
    return [
      for (final id in p.getStringList(_index) ?? const <String>[])
        if (p.getString(_key(id)) case final s?) s
    ];
  }
}
