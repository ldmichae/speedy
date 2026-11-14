import 'ride_history_store.dart';

RideHistoryStore createStore() => _UnsupportedStore();

class _UnsupportedStore implements RideHistoryStore {
  @override
  Future<void> save(String id, String json) async =>
      throw UnsupportedError('Ride history is not supported on web yet.');

  @override
  Future<void> delete(String id) async =>
      throw UnsupportedError('Ride history is not supported on web yet.');

  @override
  Future<List<String>> loadAll() async => const [];
}
