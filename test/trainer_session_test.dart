import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/models.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/devices/trainer_session.dart';

class FakeTrainer implements Trainer {
  final dataIn = StreamController<BikeData>.broadcast();
  final statusIn = StreamController<TrainerStatus>.broadcast();
  final targets = <int>[];
  bool connected = false;
  bool disposed = false;
  Object? failTargetWith;

  @override
  String get name => 'Fake';
  @override
  Stream<BikeData> get data => dataIn.stream;
  @override
  Stream<TrainerStatus> get status => statusIn.stream;
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;
  @override
  Future<void> setTargetPower(int watts) async {
    if (failTargetWith != null) throw failTargetWith!;
    targets.add(watts);
  }

  @override
  Future<void> setSimulation({
    required double gradePercent,
    double windMps = 0,
    double crr = 0.004,
    double cw = 0.51,
  }) async {}
  @override
  Future<void> dispose() async => disposed = true;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('readings carry a 3 s rolling average, timed by the injected clock',
      () async {
    final trainer = FakeTrainer();
    var t = Duration.zero;
    final session = TrainerSession(trainer, now: () => t);
    final out = <Reading>[];
    session.readings.listen(out.add);

    for (final (sec, watts) in [(0, 100), (1, 200), (2, 300), (6, 400)]) {
      t = Duration(seconds: sec);
      trainer.dataIn.add(BikeData(powerWatts: watts));
      await settle();
    }

    expect(out.map((r) => r.smoothedPower), [100, 150, 200, 400]);
    expect(out.last.data.powerWatts, 400);
    await session.dispose();
  });

  test('a packet without power has no smoothed value and keeps the window',
      () async {
    final trainer = FakeTrainer();
    final session = TrainerSession(trainer, now: () => Duration.zero);
    final out = <Reading>[];
    session.readings.listen(out.add);

    trainer.dataIn.add(const BikeData(cadenceRpm: 90));
    await settle();

    expect(out.single.smoothedPower, isNull);
    expect(out.single.data.cadenceRpm, 90);
    await session.dispose();
  });

  test('setTarget clamps to 0..1500 before reaching the trainer', () async {
    final trainer = FakeTrainer();
    final session = TrainerSession(trainer);

    await session.setTarget(-20);
    await session.setTarget(250);
    await session.setTarget(9000);

    expect(trainer.targets, [0, 250, 1500]);
    await session.dispose();
  });

  test('a failing trainer surfaces the error to the caller', () async {
    final trainer = FakeTrainer()..failTargetWith = StateError('nope');
    final session = TrainerSession(trainer);

    await expectLater(session.setTarget(100), throwsA(isA<StateError>()));
    await session.dispose();
  });

  test('connect delegates, status passes through, dispose releases', () async {
    final trainer = FakeTrainer();
    final session = TrainerSession(trainer);
    final statuses = <TrainerStatus>[];
    session.status.listen(statuses.add);

    await session.connect();
    trainer.statusIn.add(TrainerStatus.connected);
    await settle();
    expect(trainer.connected, isTrue);
    expect(statuses, [TrainerStatus.connected]);
    expect(session.name, 'Fake');

    await session.dispose();
    expect(trainer.disposed, isTrue);
  });
}
