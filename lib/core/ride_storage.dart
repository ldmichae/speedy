// Native platforms write to the documents folder; web has no filesystem here.
export 'ride_storage_stub.dart' if (dart.library.io) 'ride_storage_io.dart';
