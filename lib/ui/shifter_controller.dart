import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/ble/ble_transport.dart';
import '../devices/ble/device_scanner.dart';
import '../devices/trainer.dart';
import '../devices/zwift/zwift_controller.dart';
import 'ride_commands.dart';
import 'trainer_controller.dart';

final shifterControllerProvider =
    NotifierProvider<ShifterController, ShifterState>(ShifterController.new);

class ShifterState {
  const ShifterState({
    this.status = TrainerStatus.disconnected,
    this.deviceName,
    this.scanning = false,
    this.scanResults = const [],
    this.error,
  });

  final TrainerStatus status;
  final String? deviceName;
  final bool scanning;
  final List<BleScanResult> scanResults;
  final String? error;

  ShifterState copyWith({
    TrainerStatus? status,
    String? deviceName,
    bool? scanning,
    List<BleScanResult>? scanResults,
    String? Function()? error,
  }) =>
      ShifterState(
        status: status ?? this.status,
        deviceName: deviceName ?? this.deviceName,
        scanning: scanning ?? this.scanning,
        scanResults: scanResults ?? this.scanResults,
        error: error == null ? this.error : error(),
      );
}

/// A Zwift Click, Play or Ride. Its shift buttons move the virtual gear
/// (see [RideCommands.shift]), which only matters while simulating a route.
class ShifterController extends Notifier<ShifterState> {
  DeviceScanner? _scanner;
  String? _deviceId;
  StreamSubscription<Object?>? _buttonSub, _syncSub, _connSub;
  bool _up = false, _down = false; // held at the last notification

  BleTransport get _transport => ref.read(bleTransportProvider);
  DeviceScanner get _scan => _scanner ??= DeviceScanner(_transport);

  @override
  ShifterState build() {
    ref.onDispose(() {
      _scanner?.cancel();
      unawaited(_release());
    });
    return const ShifterState();
  }

  /// Call straight from a button press: see [DeviceScanner.start].
  Future<void> scan() async {
    state = state.copyWith(
        scanning: true, scanResults: const [], error: () => null);
    try {
      await _scan.start(
        services: [zwiftRideService, zwiftCustomService],
        onResult: (r) {
          if (state.scanResults.any((x) => x.id == r.id)) return;
          state = state.copyWith(scanResults: [...state.scanResults, r]);
          if (kIsWeb) connectTo(r); // the browser picker was the choice
        },
        onTimeout: stopScan,
      );
    } catch (e) {
      state = state.copyWith(scanning: false, error: () => 'Scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    await _scan.stop();
    state = state.copyWith(scanning: false);
  }

  Future<void> connectTo(BleScanResult device) async {
    await stopScan();
    await _release();
    final id = _deviceId = device.id;
    state = state.copyWith(
        status: TrainerStatus.connecting,
        deviceName: device.name,
        error: () => null);
    try {
      await _transport.connect(id);
      final services = await _transport.discoverServices(id);
      final service = services.contains(zwiftRideService)
          ? zwiftRideService
          : services.contains(zwiftCustomService)
              ? zwiftCustomService
              : throw StateError('This is not a Zwift Click, Play or Ride.');
      _connSub = _transport.connectionChanges(id).listen((connected) {
        if (!connected) state = state.copyWith(status: TrainerStatus.disconnected);
      });
      _buttonSub = (await _transport.subscribe(id, service, zwiftAsyncChar))
          .listen(_onButtons);
      // The handshake reply arrives here; we only need it subscribed.
      _syncSub = (await _transport.subscribe(id, service, zwiftSyncTxChar,
              indicate: true))
          .listen((_) {});
      await _transport.write(id, service, zwiftSyncRxChar, zwiftRideOn);
      state = state.copyWith(status: TrainerStatus.connected);
    } catch (e) {
      await _release();
      state = state.copyWith(status: TrainerStatus.error, error: () => '$e');
    }
  }

  /// Shifts once per press: a held button repeats in later notifications.
  void _onButtons(Uint8List bytes) {
    final p = parseZwiftShift(bytes);
    if (p == null) return;
    final commands = ref.read(rideCommandsProvider);
    if (p.up && !_up) commands.shift(1);
    if (p.down && !_down) commands.shift(-1);
    _up = p.up;
    _down = p.down;
  }

  Future<void> disconnect() async {
    await _release();
    state = state.copyWith(status: TrainerStatus.disconnected);
  }

  Future<void> _release() async {
    await _buttonSub?.cancel();
    await _syncSub?.cancel();
    await _connSub?.cancel();
    _buttonSub = _syncSub = _connSub = null;
    _up = _down = false;
    final id = _deviceId;
    _deviceId = null;
    if (id != null) {
      try {
        await _transport.disconnect(id);
      } catch (_) {}
    }
  }
}
