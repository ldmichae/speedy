import 'package:indoor_cycling/core/json_store.dart';

/// Second adapter for the JsonStore seam.
class InMemoryJsonStore implements JsonStore {
  final rides = <String, String>{};

  @override
  Future<void> save(String id, String json) async => rides[id] = json;

  @override
  Future<void> delete(String id) async => rides.remove(id);

  @override
  Future<List<String>> loadAll() async => rides.values.toList();
}
