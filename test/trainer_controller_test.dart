import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/devices/ble/ble_transport.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';

import 'fakes/in_memory_ble_transport.dart';

Future<void> until(bool Function() cond) async {
  for (var i = 0; i < 100 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(cond(), isTrue, reason: 'timed out waiting for condition');
}

void main() {
  test('simulated trainer: connect, readings, target, disconnect', () async {
    final container = ProviderContainer(overrides: [
      bleTransportProvider.overrideWithValue(InMemoryBleTransport()),
    ]);
    addTearDown(container.dispose);
    TrainerState s() => container.read(trainerControllerProvider);
    final c = container.read(trainerControllerProvider.notifier);

    await c.connectSimulated();
    await until(() => s().status == TrainerStatus.connected);
    await until(() => s().latest != null && s().smoothedPower != null);
    expect(s().deviceName, 'Simulated trainer');

    await c.setTarget(9999);
    expect(s().targetWatts, 1500); // clamped
    await c.adjustTarget(-1400);
    expect(s().targetWatts, 100);

    await c.disconnect();
    expect(s().status, TrainerStatus.disconnected);
    expect(s().latest, isNull);
    expect(s().smoothedPower, isNull);
  });

  test('the target survives reconnecting', () async {
    final container = ProviderContainer(overrides: [
      bleTransportProvider.overrideWithValue(InMemoryBleTransport()),
    ]);
    addTearDown(container.dispose);
    final c = container.read(trainerControllerProvider.notifier);

    await c.setTarget(210); // before any trainer exists
    await c.connectSimulated();
    await until(
        () => container.read(trainerControllerProvider).status ==
            TrainerStatus.connected);

    expect(container.read(trainerControllerProvider).targetWatts, 210);
    await c.disconnect();
  });

  test('scan collects each device once and stop clears scanning', () async {
    final transport = ScanningTransport([
      const BleScanResult(id: 'a', name: 'KICKR'),
      const BleScanResult(id: 'a', name: 'KICKR'),
      const BleScanResult(id: 'b', name: 'Other'),
    ]);
    final container = ProviderContainer(
        overrides: [bleTransportProvider.overrideWithValue(transport)]);
    addTearDown(container.dispose);
    final c = container.read(trainerControllerProvider.notifier);

    await c.scan();
    await until(() =>
        container.read(trainerControllerProvider).scanResults.length == 2);
    expect(container.read(trainerControllerProvider).scanning, isTrue);

    await c.stopScan();
    expect(container.read(trainerControllerProvider).scanning, isFalse);
    expect(transport.stopped, isTrue);
  });
}

/// Replays a fixed list of scan results once a scan starts.
class ScanningTransport extends InMemoryBleTransport {
  ScanningTransport(this._results);
  final List<BleScanResult> _results;
  bool stopped = false;

  @override
  Stream<BleScanResult> get scanResults => _results.isEmpty
      ? const Stream.empty()
      : Stream.fromIterable(_results);

  @override
  Future<void> stopScan() async => stopped = true;
}
