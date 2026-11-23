import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/devices/ble/ble_transport.dart';
import 'package:indoor_cycling/devices/ble/uuids.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/devices/zwift/zwift_controller.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:indoor_cycling/ui/shifter_controller.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';

import 'fakes/in_memory_ble_transport.dart';

Future<void> until(bool Function() cond) async {
  for (var i = 0; i < 100 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(cond(), isTrue, reason: 'timed out waiting for condition');
}

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

/// Protobuf varint.
List<int> varint(int v) => [
      for (; v >= 0x80; v >>= 7) (v & 0x7f) | 0x80,
      v,
    ];

/// A Ride notification with only the buttons in [held] down.
Uint8List ride(int held) =>
    bytes([0x23, 0x08, ...varint(0x3ffff & ~held), 0x1a, 0x02, 0x08, 0x00]);

void main() {
  group('parseZwiftShift', () {
    test('Click: plus is up, minus is down, 1 is released', () {
      expect(parseZwiftShift(bytes([0x37, 0x08, 0x00, 0x10, 0x01])),
          (up: true, down: false, light: false));
      expect(parseZwiftShift(bytes([0x37, 0x08, 0x01, 0x10, 0x00])),
          (up: false, down: true, light: false));
      expect(parseZwiftShift(bytes([0x37, 0x08, 0x01, 0x10, 0x01])),
          (up: false, down: false, light: false));
    });

    test('Play: right shoulder is up, left shoulder is down', () {
      expect(parseZwiftShift(bytes([0x07, 0x08, 0x00, 0x30, 0x00])),
          (up: true, down: false, light: false));
      expect(parseZwiftShift(bytes([0x07, 0x08, 0x01, 0x30, 0x00])),
          (up: false, down: true, light: false));
      expect(parseZwiftShift(bytes([0x07, 0x08, 0x00, 0x30, 0x01])),
          (up: false, down: false, light: false));
    });

    test('Ride: right side harder, left side easier, skipping analog fields',
        () {
      expect(parseZwiftShift(ride(0)), (up: false, down: false, light: false));
      expect(
          parseZwiftShift(ride(0x1000)), (up: true, down: false, light: false));
      expect(
          parseZwiftShift(ride(0x2000)), (up: true, down: false, light: false));
      expect(
          parseZwiftShift(ride(0x0100)), (up: false, down: true, light: false));
      expect(
          parseZwiftShift(ride(0x0200)), (up: false, down: true, light: false));
      // Power-up and the other buttons switch the headlight; on/off does not.
      for (final b in [0x0400, 0x4000, 0x0001, 0x0080]) {
        expect(parseZwiftShift(ride(b)), (up: false, down: false, light: true));
      }
      expect(parseZwiftShift(ride(0x0800)),
          (up: false, down: false, light: false));
    });

    test('Click v2, as captured from one', () {
      expect(parseZwiftShift(bytes([0x23, 0x08, 0xff, 0xdf, 0xff, 0xff, 0x0f])),
          (up: true, down: false, light: false)); // harder
      expect(parseZwiftShift(bytes([0x23, 0x08, 0xff, 0xfd, 0xff, 0xff, 0x0f])),
          (up: false, down: true, light: false)); // easier
    });

    test('battery, keep-alive and truncated packets are ignored', () {
      expect(parseZwiftShift(bytes([0x19, 0x08, 0x50])), isNull);
      expect(parseZwiftShift(bytes([0x15])), isNull);
      expect(parseZwiftShift(bytes([0x23, 0x08, 0xff])), isNull);
      expect(parseZwiftShift(bytes([])), isNull);
    });
  });

  test('shifters shift gears on the road, and move the target in ERG',
      () async {
    final buttons = StreamController<Uint8List>.broadcast();
    final t = ShifterTransport(buttons.stream);
    final container = ProviderContainer(
        overrides: [bleTransportProvider.overrideWithValue(t)]);
    addTearDown(container.dispose);
    TrainerState s() => container.read(trainerControllerProvider);
    final trainer = container.read(trainerControllerProvider.notifier);
    final shifter = container.read(shifterControllerProvider.notifier);

    await trainer.connectTo(const BleScanResult(id: 'k', name: 'KICKR'));
    await shifter.connectTo(const BleScanResult(id: 'z', name: 'Zwift Click'));
    expect(container.read(shifterControllerProvider).status,
        TrainerStatus.connected);
    expect(t.rideOn, [zwiftRideOn]);

    final ergTarget = s().targetWatts;
    void press(int plus, int minus) =>
        buttons.add(bytes([0x37, 0x08, plus, 0x10, minus]));

    press(0, 1); // ERG: up 5 W
    press(1, 1);
    await pumpEventQueue();
    expect(s().gear, TrainerState.neutralGear);

    // ERG: the press moved the target 5 W, like the arrow keys.
    expect(s().targetWatts, ergTarget + 5);

    // On the road (a free ride), then at a 3% grade as a route would set.
    container.read(rideSessionProvider.notifier).setRoad(true);
    await trainer.setGrade(3);
    expect(t.lastGrade, 3.0);

    press(0, 1);
    press(0, 1); // still held: no second shift
    await until(() => t.lastGrade == 3.5);
    expect(s().gear, TrainerState.neutralGear + 1);

    press(1, 1);
    press(1, 0);
    await until(() => t.lastGrade == 3.0);

    await trainer.setGrade(4); // the gear rides on top of the road
    press(1, 1);
    press(1, 0);
    await until(() => t.lastGrade == 3.5);
    expect(s().gear, TrainerState.neutralGear - 1);
    expect(s().gradePercent, 4.0);

    // Speed comes from power, the road and momentum, so a shift doesn't jump
    // it to the trainer's flywheel speed. Flags 0x0040: speed, then 200 W.
    t.emitBikeData([0x40, 0x00, 0x10, 0x27, 0xc8, 0x00]); // 100 km/h seeds it
    await until(() => s().latest?.speedKph == 100);
    await trainer.shift(5);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    t.emitBikeData([0x40, 0x00, 0xf4, 0x01, 0xc8, 0x00]); // trainer: 5 km/h
    await until(() => s().latest?.speedKph != 100);
    expect(t.lastGrade, 6.0);
    // Slowing under drag (~18 km/h a second at 100), not snapping to 5.
    expect(s().latest!.speedKph, inExclusiveRange(60, 100));

    await trainer.setTarget(150); // ERG: the trainer's speed again
    t.emitBikeData([0x40, 0x00, 0xd0, 0x07, 0xc8, 0x00]); // 20 km/h
    await until(() => s().latest?.speedKph == 20);

    await shifter.disconnect();
    await trainer.disconnect();
  });
}

/// An FTMS trainer and a Zwift Click on one fake radio.
class ShifterTransport extends InMemoryBleTransport {
  ShifterTransport(this.buttons)
      : super(services: [ftmsService, zwiftRideService]);
  final Stream<Uint8List> buttons;
  final rideOn = <Uint8List>[];

  /// Grade (%) of the last simulation command sent to the trainer.
  double? get lastGrade {
    final w = writes.lastWhere((w) => w[0] == 0x11, orElse: () => bytes([]));
    return w.isEmpty
        ? null
        : ByteData.sublistView(w).getInt16(3, Endian.little) / 100;
  }

  @override
  Future<Stream<Uint8List>> subscribe(
      String deviceId, String service, String characteristic,
      {bool indicate = false}) async {
    if (characteristic == zwiftAsyncChar) return buttons;
    if (characteristic == zwiftSyncTxChar) return const Stream.empty();
    return super
        .subscribe(deviceId, service, characteristic, indicate: indicate);
  }

  @override
  Future<void> write(String deviceId, String service, String characteristic,
      Uint8List value) async {
    if (characteristic == zwiftSyncRxChar) return rideOn.add(value);
    return super.write(deviceId, service, characteristic, value);
  }
}
