import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/models.dart';
import 'package:indoor_cycling/devices/ftms/ftms_trainer.dart';
import 'package:indoor_cycling/devices/trainer.dart';

import 'fakes/in_memory_ble_transport.dart';

FtmsTrainer trainerOn(InMemoryBleTransport t) =>
    FtmsTrainer(transport: t, deviceId: 'kickr', deviceName: 'KICKR');

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('connect requests control, starts, and reports connected', () async {
    final ble = InMemoryBleTransport();
    final trainer = trainerOn(ble);
    final statuses = <TrainerStatus>[];
    trainer.status.listen(statuses.add);

    await trainer.connect();
    await settle();

    expect(ble.writtenOpcodes, [0x00, 0x07]); // request control, start
    expect(statuses, [TrainerStatus.connecting, TrainerStatus.connected]);
    await trainer.dispose();
  });

  test('connect fails with a clear message if another app holds control',
      () async {
    final ble = InMemoryBleTransport(
        replyFor: (op, n) => op == 0x00 ? 0x04 : null); // operationFailed
    final trainer = trainerOn(ble);

    await expectLater(
      trainer.connect(),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('Close the Wahoo/Zwift'))),
    );
    await trainer.dispose();
  });

  test('connect rejects a device without the Fitness Machine Service',
      () async {
    final ble = InMemoryBleTransport(services: const []);
    final trainer = trainerOn(ble);

    await expectLater(trainer.connect(), throwsA(isA<StateError>()));
    expect(ble.disconnectCalls, 1);
    await trainer.dispose();
  });

  test('setTargetPower re-requests control once if it was lost', () async {
    final ble = InMemoryBleTransport(
        replyFor: (op, n) => op == 0x05 && n == 0 ? 0x05 : null);
    final trainer = trainerOn(ble);
    await trainer.connect();

    await trainer.setTargetPower(180);

    // connect: 0,7 · first set fails (not permitted) · regain control: 0,7 · retry
    expect(ble.writtenOpcodes, [0x00, 0x07, 0x05, 0x00, 0x07, 0x05]);
    expect(ble.writes.last.sublist(1), [180, 0]); // little-endian 180 W
    await trainer.dispose();
  });

  test('setTargetPower surfaces a persistent failure', () async {
    final ble =
        InMemoryBleTransport(replyFor: (op, n) => op == 0x05 ? 0x03 : null);
    final trainer = trainerOn(ble);
    await trainer.connect();

    await expectLater(trainer.setTargetPower(180), throwsA(isA<StateError>()));
    await trainer.dispose();
  });

  test('bike data is parsed and truncated packets are dropped', () async {
    final ble = InMemoryBleTransport();
    final trainer = trainerOn(ble);
    final readings = <BikeData>[];
    trainer.data.listen(readings.add);
    await trainer.connect();

    // flags 0x0044 = cadence + power; speed present (bit 0 clear).
    ble.emitBikeData([0x44, 0x00, 0xB8, 0x0B]); // claims more fields than sent
    ble.emitBikeData([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0x96, 0x00]);
    await settle();

    expect(readings, hasLength(1));
    expect(readings.single.speedKph, closeTo(30.0, 0.01));
    expect(readings.single.cadenceRpm, 90);
    expect(readings.single.powerWatts, 150);
    await trainer.dispose();
  });

  test('a dropped link is reported as disconnected', () async {
    final ble = InMemoryBleTransport();
    final trainer = trainerOn(ble);
    final statuses = <TrainerStatus>[];
    trainer.status.listen(statuses.add);
    await trainer.connect();

    ble.dropConnection();
    await settle();

    expect(statuses.last, TrainerStatus.disconnected);
    await trainer.dispose();
  });
}
