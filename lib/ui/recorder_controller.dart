import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/ride_export.dart';
import '../core/ride_record.dart';
import '../core/ride_recording.dart';
import '../core/ride_stats.dart';
import '../devices/trainer.dart';
import 'ride_history_provider.dart';
import 'rider_profile_controller.dart';
import 'trainer_controller.dart';

class RecordingState {
  const RecordingState({
    this.status = RecStatus.idle,
    this.samples = const [],
    this.elapsed = Duration.zero,
  });

  final RecStatus status;

  /// The recording's live list; do not mutate. A fresh [RecordingState] is
  /// published every tick, so watchers rebuild.
  final List<RideSample> samples;
  final Duration elapsed;
}

final recorderProvider =
    NotifierProvider<RecorderController, RecordingState>(RecorderController.new);

/// Overridable so tests can save without touching the filesystem.
final rideExporterProvider = Provider<
    Future<String> Function(List<RideSample>, DateTime, RideFormat)>(
  (ref) => exportRide,
);

final rideFormatProvider =
    NotifierProvider<RideFormatController, RideFormat>(RideFormatController.new);

class RideFormatController extends PersistedNotifier<RideFormat> {
  static const _key = 'rideFormat';

  @override
  RideFormat get defaults => RideFormat.fit;

  @override
  RideFormat? read(SharedPreferences p) {
    final name = p.getString(_key);
    return RideFormat.values.where((f) => f.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences p, RideFormat f) => p.setString(_key, f.name);

  void set(RideFormat f) => put(f);
}

/// Schedules sampling and publishes state; the rules live in [Recording].
class RecorderController extends Notifier<RecordingState> {
  final _recording = Recording();
  final _clock = Stopwatch()..start();
  Timer? _timer;

  @override
  RecordingState build() {
    ref.onDispose(() => _timer?.cancel());
    // No data without a trainer, so don't keep the clock running.
    ref.listen(trainerControllerProvider.select((s) => s.status), (_, status) {
      if (status != TrainerStatus.connected) pause();
    });
    return const RecordingState();
  }

  SampleInput _input() {
    final s = ref.read(trainerControllerProvider);
    return SampleInput(
        target: s.targetWatts, data: s.latest, smoothedPower: s.smoothedPower);
  }

  void start() {
    if (_recording.status != RecStatus.idle) return;
    _recording.start(_clock.elapsed, DateTime.now(), _input());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recording.add(_clock.elapsed, _input());
      _publish();
    });
    _publish();
  }

  void pause() {
    _recording.pause(_clock.elapsed);
    _publish();
  }

  void resume() {
    _recording.resume(_clock.elapsed);
    _publish();
  }

  /// Adds the ride to history, exports it in the chosen format, and resets.
  /// Returns the export path. Throws if either step fails, in which case the
  /// recording is kept; retrying overwrites the same history record.
  Future<String> save() async {
    final started = _recording.startedAt ?? DateTime.now();
    final samples = List.of(_recording.samples);
    final record = RideRecord(
      startedAt: started,
      samples: samples,
      kcal: rideKcal(samples, ref.read(riderProfileProvider)),
    );
    await ref
        .read(rideHistoryStoreProvider)
        .save(record.id, jsonEncode(record.toJson()));
    final path = await ref
        .read(rideExporterProvider)(samples, started, ref.read(rideFormatProvider));
    ref.invalidate(rideHistoryProvider);
    discard();
    return path;
  }

  void discard() {
    _timer?.cancel();
    _timer = null;
    _recording.reset();
    state = const RecordingState();
  }

  void _publish() {
    state = RecordingState(
      status: _recording.status,
      samples: _recording.samples,
      elapsed: _recording.elapsed(_clock.elapsed),
    );
  }
}
