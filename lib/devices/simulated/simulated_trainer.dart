import 'dart:async';
import 'dart:math';

import '../../core/models.dart';
import '../trainer.dart';

/// A fake trainer so the whole app can be developed and tested without
/// hardware. In ERG mode, power eases toward the target like a real unit.
class SimulatedTrainer implements Trainer {
  final _data = StreamController<BikeData>.broadcast();
  final _status = StreamController<TrainerStatus>.broadcast();
  final _rng = Random(7);
  final _clock = Stopwatch();
  Timer? _timer;
  int? _target;
  double? _grade;
  double _crr = 0.004, _cw = 0.51;
  double _power = 0;
  bool _disposed = false;

  @override
  String get name => 'Simulated trainer';
  @override
  Stream<TrainerStatus> get status => _status.stream;
  @override
  Stream<BikeData> get data => _data.stream;

  @override
  Future<void> connect() async {
    _status.add(TrainerStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _status.add(TrainerStatus.connected);
  }

  void _tick() {
    final target = _target;
    if (_grade != null) {
      _power =
          150; // the rider pedals; the grade changes the speed, not the power
    } else if (target != null) {
      _power += (target - _power) * 0.25;
    } else {
      _power = 120 + _rng.nextDouble() * 20;
    }
    final watts = max(0, (_power + (_rng.nextDouble() - 0.5) * 8).round());
    // Placeholder power-to-speed curve; the real physics model comes later.
    final speed = _grade == null
        ? 4.2 * pow(max(watts, 1), 1 / 3)
        : simulatedSpeedKph(watts, _grade!, crr: _crr, cw: _cw);
    _data.add(BikeData(
      powerWatts: watts,
      cadenceRpm: 88 + (_rng.nextDouble() - 0.5) * 6,
      speedKph: speed.toDouble(),
      elapsedSeconds: _clock.elapsed.inSeconds,
    ));
  }

  @override
  Future<void> setTargetPower(int watts) async {
    _target = watts;
    _grade = null; // ERG replaces SIM, as on a real trainer
  }

  @override
  Future<void> setSimulation({
    required double gradePercent,
    double windMps = 0,
    double crr = 0.004,
    double cw = 0.51,
  }) async {
    _grade = gradePercent;
    _crr = crr;
    _cw = cw;
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _clock.stop();
    if (!_disposed) _status.add(TrainerStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _timer?.cancel();
    _disposed = true;
    await _data.close();
    await _status.close();
  }
}

/// Steady speed (km/h) for a rider putting out [watts] on [gradePercent]:
/// solves watts = v * (m g (grade + crr) + cw v^2) for v. Rider + bike are
/// taken as 85 kg; real trainers use the weight set in their own app.
double simulatedSpeedKph(int watts, double gradePercent,
    {double crr = 0.004, double cw = 0.51, double massKg = 85}) {
  double power(double v) =>
      v * (massKg * 9.81 * (gradePercent / 100 + crr) + cw * v * v);
  var lo = 0.0, hi = 30.0; // m/s
  // On a steep enough climb the rider can barely move: floor at walking pace.
  // Not pedalling on the flat or uphill is standing still.
  if (power(0.5) > watts) return watts > 0 ? 1.8 : 0;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    power(mid) < watts ? lo = mid : hi = mid;
  }
  return lo * 3.6;
}

/// Speed (km/h) [seconds] after riding at [kph] with [watts] on
/// [gradePercent]: the forces of [simulatedSpeedKph] plus the rider's
/// momentum, so speed builds and fades instead of jumping. Left alone it
/// settles on [simulatedSpeedKph].
double nextSpeedKph(double kph, num watts, double gradePercent, double seconds,
    {double crr = 0.004, double cw = 0.51, double massKg = 85}) {
  if (seconds <= 0) return kph;
  final steps = (seconds / 0.25).ceil(); // short steps keep drag stable
  final dt = seconds / steps;
  var v = kph / 3.6;
  for (var i = 0; i < steps; i++) {
    final drive = watts / max(v, 0.5); // pedal force, finite from a standstill
    final resist = massKg * 9.81 * (gradePercent / 100 + crr) + cw * v * v;
    v = max(0, v + (drive - resist) / massKg * dt);
  }
  return v * 3.6;
}
