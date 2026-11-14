import 'ride_history_store_stub.dart'
    if (dart.library.io) 'ride_history_store_io.dart' as impl;

/// Where saved rides are kept for the history viewer. Files on native
/// platforms; unsupported on web for now.
abstract class RideHistoryStore {
  /// Writes (or overwrites) the ride with this [id].
  Future<void> save(String id, String json);

  /// Removes the ride with this [id]; a no-op if it is already gone.
  Future<void> delete(String id);

  /// Every stored ride's JSON, in no particular order.
  Future<List<String>> loadAll();
}

RideHistoryStore createRideHistoryStore() => impl.createStore();
