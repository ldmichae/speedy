import 'dart:async';

import '../core/models.dart';
import '../core/smoothing.dart';
import 'trainer.dart';

/// One trainer reading plus the signal derived from it.
class Reading {
  const Reading(this.data, this.smoothedPower);
  final BikeData data;

  /// Rolling 3 s average; null if this packet carried no power.
  final double? smoothedPower;
}

/// A live connection to one [Trainer]: connect it, send ERG targets, and get
/// [Reading]s with power already smoothed. Owns the clock and the smoother,
/// so callers never see raw timing. [now] is injectable for tests.
class TrainerSession {
  TrainerSession(this.trainer, {Duration Function()? now}) {
    final clock = Stopwatch()..start();
    _now = now ?? (() => clock.elapsed);
    _dataSub = trainer.data.listen(_onData);
  }

  static const maxTargetWatts = 1500;
  static int clampTarget(int watts) => watts.clamp(0, maxTargetWatts).toInt();

  /// Steepest grades sent to the trainer; real units cap near these anyway.
  static const maxGrade = 15.0, minGrade = -10.0;
  static double clampGrade(double g) => g.clamp(minGrade, maxGrade).toDouble();

  final Trainer trainer;
  late final Duration Function() _now;
  final _smoother = PowerSmoother();
  final _readings = StreamController<Reading>.broadcast();
  late final StreamSubscription<BikeData> _dataSub;

  String get name => trainer.name;
  Stream<TrainerStatus> get status => trainer.status;
  Stream<Reading> get readings => _readings.stream;

  Future<void> connect() => trainer.connect();

  /// Holds [watts] (clamped to 0..[maxTargetWatts]) in ERG mode.
  Future<void> setTarget(int watts) =>
      trainer.setTargetPower(clampTarget(watts));

  /// Simulates road [gradePercent] (clamped to a rideable range).
  Future<void> setSimulation(double gradePercent) =>
      trainer.setSimulation(gradePercent: clampGrade(gradePercent));

  void _onData(BikeData d) {
    final p = d.powerWatts;
    _readings.add(Reading(d, p == null ? null : _smoother.add(p, _now())));
  }

  Future<void> dispose() async {
    await _dataSub.cancel();
    await _readings.close();
    try {
      await trainer.dispose();
    } catch (_) {}
  }
}
