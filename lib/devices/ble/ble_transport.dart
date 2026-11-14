import 'dart:typed_data';

class BleScanResult {
  const BleScanResult({required this.id, required this.name});
  final String id;
  final String name;
}

/// Thin seam over the BLE package. FtmsTrainer only depends on this, so the
/// package can be swapped and the trainer logic tested with a fake.
abstract class BleTransport {
  Stream<BleScanResult> get scanResults;

  /// On web this opens the browser's device picker and must be called
  /// directly from a user gesture.
  Future<void> startScan({required List<String> services});
  Future<void> stopScan();

  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);

  /// Emits true/false as the device connects/disconnects.
  Stream<bool> connectionChanges(String deviceId);

  /// Returns normalized 128-bit service UUIDs.
  Future<List<String>> discoverServices(String deviceId);

  /// Enables notifications (or indications) and returns the value stream.
  Future<Stream<Uint8List>> subscribe(
    String deviceId,
    String service,
    String characteristic, {
    bool indicate = false,
  });

  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
  );
}
