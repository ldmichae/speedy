import '../core/models.dart';

enum TrainerStatus { disconnected, connecting, connected, error }

/// Everything the app needs from a smart trainer. The ride screen, workout
/// engine and (later) world sim only ever talk to this interface.
abstract class Trainer {
  String get name;

  Stream<TrainerStatus> get status;
  Stream<BikeData> get data;

  Future<void> connect();
  Future<void> disconnect();

  /// ERG mode: hold [watts] regardless of cadence.
  Future<void> setTargetPower(int watts);

  /// SIM mode: the trainer simulates road grade, wind and drag.
  Future<void> setSimulation({
    required double gradePercent,
    double windMps = 0,
    double crr = 0.004,
    double cw = 0.51,
  });

  Future<void> dispose();
}
