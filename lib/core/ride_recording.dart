import 'models.dart';

/// One row of a recorded ride, sampled once per second of *moving* time
/// (paused time is not counted).
class RideSample {
  const RideSample({
    required this.t,
    this.target,
    this.power,
    this.smoothedPower,
    this.cadence,
    this.speed,
    this.heartRate,
  });

  /// Seconds since the ride started, excluding pauses.
  final double t;
  final int? target;
  final int? power;
  final double? smoothedPower;
  final double? cadence;
  final double? speed;
  final int? heartRate;
}

enum RecStatus { idle, recording, paused }

/// The rules of a ride recording: moving time excludes pauses, samples only
/// land while recording. Time is passed in (any monotonic clock) so this is
/// deterministic; scheduling and the data source belong to the caller.
class Recording {
  final _samples = <RideSample>[];
  RecStatus _status = RecStatus.idle;
  Duration _banked = Duration.zero; // moving time before the current run
  Duration _since = Duration.zero; // clock value when the current run began
  DateTime? _startedAt;

  RecStatus get status => _status;
  List<RideSample> get samples => _samples;
  DateTime? get startedAt => _startedAt;

  Duration elapsed(Duration now) =>
      _status == RecStatus.recording ? _banked + (now - _since) : _banked;

  /// Starts a new ride and records its first sample.
  void start(Duration now, DateTime wallClock, SampleInput input) {
    if (_status != RecStatus.idle) return;
    _startedAt = wallClock;
    _since = now;
    _status = RecStatus.recording;
    add(now, input);
  }

  void pause(Duration now) {
    if (_status != RecStatus.recording) return;
    _banked = elapsed(now);
    _status = RecStatus.paused;
  }

  void resume(Duration now) {
    if (_status != RecStatus.paused) return;
    _since = now;
    _status = RecStatus.recording;
  }

  /// Ignored unless recording, so late timer ticks can't leak into a pause.
  void add(Duration now, SampleInput input) {
    if (_status != RecStatus.recording) return;
    final d = input.data;
    _samples.add(RideSample(
      t: elapsed(now).inMilliseconds / 1000,
      target: input.target,
      power: d?.powerWatts,
      smoothedPower: input.smoothedPower,
      cadence: d?.cadenceRpm,
      speed: d?.speedKph,
      heartRate: d?.heartRate,
    ));
  }

  void reset() {
    _samples.clear();
    _status = RecStatus.idle;
    _banked = Duration.zero;
    _startedAt = null;
  }
}

/// What the trainer says at one instant.
class SampleInput {
  const SampleInput({required this.target, this.data, this.smoothedPower});
  final int target;
  final BikeData? data;
  final double? smoothedPower;
}
