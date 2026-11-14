import 'package:indoor_cycling/core/ride_history_store.dart';

/// Second adapter for the RideHistoryStore seam.
class InMemoryRideHistoryStore implements RideHistoryStore {
  final rides = <String, String>{};

  @override
  Future<void> save(String id, String json) async => rides[id] = json;

  @override
  Future<void> delete(String id) async => rides.remove(id);

  @override
  Future<List<String>> loadAll() async => rides.values.toList();
}
