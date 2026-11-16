import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/ble/ble_transport.dart';
import '../devices/ble/device_scanner.dart';
import '../devices/ble/uuids.dart';
import '../devices/ftms/ftms_parser.dart';
import '../devices/trainer.dart';
import 'trainer_controller.dart';

final heartRateControllerProvider =
    NotifierProvider<HeartRateController, HeartRateState>(
        HeartRateController.new);

class HeartRateState {
  const HeartRateState({
    this.status = TrainerStatus.disconnected,
    this.deviceName,
    this.bpm,
    this.scanning = false,
    this.scanResults = const [],
    this.error,
  });

  final TrainerStatus status;
  final String? deviceName;

  /// Latest strap reading; null when not connected or the strap lost contact.
  final int? bpm;
  final bool scanning;
  final List<BleScanResult> scanResults;
  final String? error;
}

/// A Bluetooth heart rate strap (standard Heart Rate Service). Its bpm
/// replaces the trainer's own heart rate in [TrainerState.latest].
class HeartRateController extends Notifier<HeartRateState> {
  DeviceScanner? _scanner;
  String? _deviceId;
  StreamSubscription<Object?>? _hrSub, _connSub;

  BleTransport get _transport => ref.read(bleTransportProvider);
  DeviceScanner get _scan => _scanner ??= DeviceScanner(_transport);

  @override
  HeartRateState build() {
    ref.onDispose(() {
      _scanner?.cancel();
      unawaited(_release());
    });
    return const HeartRateState();
  }

  void _set({
    TrainerStatus? status,
    String? deviceName,
    int? Function()? bpm,
    bool? scanning,
    List<BleScanResult>? scanResults,
    String? Function()? error,
  }) {
    final s = state;
    state = HeartRateState(
      status: status ?? s.status,
      deviceName: deviceName ?? s.deviceName,
      bpm: bpm == null ? s.bpm : bpm(),
      scanning: scanning ?? s.scanning,
      scanResults: scanResults ?? s.scanResults,
      error: error == null ? s.error : error(),
    );
  }

  /// Call straight from a button press: see [DeviceScanner.start].
  Future<void> scan() async {
    _set(scanning: true, scanResults: const [], error: () => null);
    try {
      await _scan.start(
        services: [heartRateService],
        onResult: (r) {
          if (state.scanResults.any((x) => x.id == r.id)) return;
          _set(scanResults: [...state.scanResults, r]);
          if (kIsWeb) connectTo(r); // the browser picker was the choice
        },
        onTimeout: stopScan,
      );
    } catch (e) {
      _set(scanning: false, error: () => 'Scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    await _scan.stop();
    _set(scanning: false);
  }

  Future<void> connectTo(BleScanResult device) async {
    await stopScan();
    await _release();
    _deviceId = device.id;
    _set(
        status: TrainerStatus.connecting,
        deviceName: device.name,
        bpm: () => null,
        error: () => null);
    try {
      await _transport.connect(device.id);
      final services = await _transport.discoverServices(device.id);
      if (!services.contains(heartRateService)) {
        throw StateError('This device does not expose the Heart Rate Service.');
      }
      _connSub = _transport.connectionChanges(device.id).listen((connected) {
        if (!connected) {
          _set(status: TrainerStatus.disconnected, bpm: () => null);
        }
      });
      _hrSub = (await _transport.subscribe(
              device.id, heartRateService, heartRateMeasurementChar))
          .listen((bytes) => _set(bpm: () => parseHeartRateMeasurement(bytes)));
      _set(status: TrainerStatus.connected);
    } catch (e) {
      await _release();
      _set(status: TrainerStatus.error, error: () => '$e');
    }
  }

  Future<void> disconnect() async {
    await _release();
    _set(status: TrainerStatus.disconnected, bpm: () => null);
  }

  Future<void> _release() async {
    await _hrSub?.cancel();
    await _connSub?.cancel();
    _hrSub = _connSub = null;
    final id = _deviceId;
    _deviceId = null;
    if (id != null) {
      try {
        await _transport.disconnect(id);
      } catch (_) {}
    }
  }
}
