import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'ble_transport.dart';
import 'uuids.dart';

/// The only file that imports universal_ble. If the package API shifts
/// between versions, this is the one place to fix.
///
/// universal_ble exposes global callbacks, so create exactly one instance
/// (see bleTransportProvider).
class UniversalBleTransport implements BleTransport {
  UniversalBleTransport() {
    UniversalBle.onScanResult = (BleDevice device) {
      final String? n = device.name;
      _scan.add(BleScanResult(
        id: device.deviceId,
        name: (n == null || n.isEmpty) ? 'Unnamed device' : n,
      ));
    };
    UniversalBle.onConnectionChange = (BleConnectionChange change) {
      _conn.add((change.deviceId, change.isConnected));
    };
    UniversalBle.onValueChange = (BleCharacteristicValue v) {
      _values.add((v.deviceId, normalizeUuid(v.characteristicId), v.value));
    };
  }

  final _scan = StreamController<BleScanResult>.broadcast();
  final _conn = StreamController<(String, bool)>.broadcast();
  final _values = StreamController<(String, String, Uint8List)>.broadcast();

  @override
  Stream<BleScanResult> get scanResults => _scan.stream;

  @override
  Future<void> startScan({required List<String> services}) {
    return UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: services),
      // Web Bluetooth only exposes services declared up front.
      platformConfig: PlatformConfig(
        web: WebOptions(optionalServices: services),
      ),
    );
  }

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) => UniversalBle.connect(deviceId);

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Stream<bool> connectionChanges(String deviceId) => _conn.stream
      .where((e) => e.$1.toLowerCase() == deviceId.toLowerCase())
      .map((e) => e.$2);

  @override
  Future<List<String>> discoverServices(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);
    return services.map((s) => normalizeUuid(s.uuid)).toList();
  }

  @override
  Future<Stream<Uint8List>> subscribe(
    String deviceId,
    String service,
    String characteristic, {
    bool indicate = false,
  }) async {
    final wanted = normalizeUuid(characteristic);
    // Build the filtered stream first so no early packet is missed.
    final stream = _values.stream
        .where((e) =>
            e.$1.toLowerCase() == deviceId.toLowerCase() && e.$2 == wanted)
        .map((e) => e.$3);
    if (indicate) {
      await UniversalBle.subscribeIndications(
          deviceId, service, characteristic);
    } else {
      await UniversalBle.subscribeNotifications(
          deviceId, service, characteristic);
    }
    return stream;
  }

  @override
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
  ) =>
      writeWithFallback((withoutResponse) => UniversalBle.write(
            deviceId,
            service,
            characteristic,
            value,
            withoutResponse: withoutResponse,
          ));
}

/// Writes with a response (so a failure is reported), or without one when
/// the characteristic only takes that: newer Zwift Click firmware
/// dropped write-with-response on its handshake characteristic.
Future<void> writeWithFallback(
    Future<void> Function(bool withoutResponse) write) async {
  try {
    await write(false);
  } on UniversalBleException catch (e) {
    if (e.code != UniversalBleErrorCode.characteristicDoesNotSupportWrite) {
      rethrow;
    }
    await write(true);
  }
}
