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
    if (target != null) {
      _power += (target - _power) * 0.25;
    } else {
      _power = 120 + _rng.nextDouble() * 20;
    }
    final watts = max(0, (_power + (_rng.nextDouble() - 0.5) * 8).round());
    // Placeholder power-to-speed curve; the real physics model comes later.
    final speed = 4.2 * pow(max(watts, 1), 1 / 3);
    _data.add(BikeData(
      powerWatts: watts,
      cadenceRpm: 88 + (_rng.nextDouble() - 0.5) * 6,
      speedKph: speed.toDouble(),
      elapsedSeconds: _clock.elapsed.inSeconds,
    ));
  }

  @override
  Future<void> setTargetPower(int watts) async => _target = watts;

  @override
  Future<void> setSimulation({
    required double gradePercent,
    double windMps = 0,
    double crr = 0.004,
    double cw = 0.51,
  }) async {
    // Not modelled yet.
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
