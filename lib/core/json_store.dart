import 'json_store_stub.dart' if (dart.library.io) 'json_store_io.dart' as impl;

/// Keeps JSON documents by id, one namespace per kind of thing (rides,
/// tours). Files on native platforms; shared preferences on web.
abstract class JsonStore {
  /// Writes (or overwrites) the document with this [id].
  Future<void> save(String id, String json);

  /// Removes the document with this [id]; a no-op if it is already gone.
  Future<void> delete(String id);

  /// Every stored document, in no particular order.
  Future<List<String>> loadAll();
}

/// The store for [namespace]. With [webSupported] false the web adapter
/// refuses writes (ride history is not stored in a browser yet).
JsonStore createJsonStore(String namespace, {bool webSupported = true}) =>
    impl.createStore(namespace, webSupported: webSupported);
