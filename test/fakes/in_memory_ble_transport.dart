import 'dart:async';
import 'dart:typed_data';

import 'package:indoor_cycling/devices/ble/ble_transport.dart';
import 'package:indoor_cycling/devices/ble/uuids.dart';

/// Second adapter for the BleTransport seam: a scripted trainer in memory.
///
/// Every Control Point write is recorded in [writes] and answered with an
/// indication carrying the result [replyFor] returns (default: success).
class InMemoryBleTransport implements BleTransport {
  InMemoryBleTransport({this.services, this.replyFor});

  /// Services the "device" advertises; defaults to FTMS only.
  final List<String>? services;

  /// Result code (0x01 = success, 0x05 = control not permitted ...) for the
  /// n-th (0-based) write of [opcode]. Return null for the default.
  final int? Function(int opcode, int nth)? replyFor;

  final writes = <Uint8List>[];
  int disconnectCalls = 0;
  final _counts = <int, int>{};
  final _bike = StreamController<Uint8List>.broadcast();
  final _cp = StreamController<Uint8List>.broadcast();
  final _conn = StreamController<bool>.broadcast();

  List<int> get writtenOpcodes => [for (final w in writes) w[0]];

  /// Pushes an Indoor Bike Data notification, as the trainer would.
  void emitBikeData(List<int> bytes) => _bike.add(Uint8List.fromList(bytes));

  /// Simulates the trainer dropping the link.
  void dropConnection() => _conn.add(false);

  @override
  Stream<BleScanResult> get scanResults => const Stream.empty();
  @override
  Future<void> startScan({required List<String> services}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> disconnect(String deviceId) async => disconnectCalls++;
  @override
  Stream<bool> connectionChanges(String deviceId) => _conn.stream;
  @override
  Future<List<String>> discoverServices(String deviceId) async =>
      services ?? [ftmsService];

  @override
  Future<Stream<Uint8List>> subscribe(
    String deviceId,
    String service,
    String characteristic, {
    bool indicate = false,
  }) async =>
      characteristic == ftmsControlPointChar ? _cp.stream : _bike.stream;

  @override
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
  ) async {
    writes.add(value);
    final opcode = value[0];
    final nth = _counts.update(opcode, (n) => n + 1, ifAbsent: () => 0);
    final result = replyFor?.call(opcode, nth) ?? 0x01;
    scheduleMicrotask(() => _cp.add(Uint8List.fromList([0x80, opcode, result])));
  }
}
