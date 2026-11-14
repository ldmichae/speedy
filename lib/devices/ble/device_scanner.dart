import 'dart:async';

import 'ble_transport.dart';

/// Runs one scan at a time and stops it after [timeout].
class DeviceScanner {
  DeviceScanner(this._transport, {this.timeout = const Duration(seconds: 15)});

  final BleTransport _transport;
  final Duration timeout;
  StreamSubscription<BleScanResult>? _sub;
  Timer? _timer;

  /// Call straight from a button press: on web the browser's device picker
  /// only opens while the click's user gesture is still active, so there must
  /// be no awaits before startScan.
  Future<void> start({
    required List<String> services,
    required void Function(BleScanResult) onResult,
    required void Function() onTimeout,
  }) async {
    _sub?.cancel();
    _sub = _transport.scanResults.listen(onResult);
    await _transport.startScan(services: services);
    _timer?.cancel();
    _timer = Timer(timeout, onTimeout);
  }

  Future<void> stop() async {
    cancel();
    try {
      await _transport.stopScan();
    } catch (_) {}
  }

  /// Drops listeners without touching the radio (for disposal).
  void cancel() {
    _timer?.cancel();
    _sub?.cancel();
    _sub = null;
  }
}
