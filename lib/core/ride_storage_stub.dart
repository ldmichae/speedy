import 'dart:typed_data';

/// Saves [bytes] as a ride file and returns where it went.
Future<String> saveRideFile(Uint8List bytes, String ext, DateTime startedAt) async =>
    throw UnsupportedError('Saving rides is not supported on web yet.');
