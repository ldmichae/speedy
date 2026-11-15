import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/power_fun.dart';
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

enum StopChoice { save, discard, keepGoing }

/// What the rider sees when ending a ride, from [RecorderController.requestStop].
class StopSummary {
  const StopSummary(
      {required this.stats, required this.joules, required this.wasRecording});

  final RideStats stats;
  final double joules;

  /// Whether the ride was running (not already paused) when Stop was pressed.
  final bool wasRecording;
}

final recorderProvider =
    NotifierProvider<RecorderController, RecordingState>(RecorderController.new);

/// Overridable so tests can save without touching the filesystem.
final rideExporterProvider = Provider<
    Future<String> Function(List<RideSample>, DateTime, RideFormat)>(
  (ref) => exportRide,
);

/// Totals for the ride being recorded, recomputed once per recorded sample.
final liveRideStatsProvider = Provider<RideStats>((ref) {
  final samples = ref.watch(recorderProvider.select((r) => r.samples));
  final profile = ref.watch(riderProfileProvider);
  ref.watch(recorderProvider.select((r) => r.samples.length));
  return RideStats.of(samples, kcal: rideKcal(samples, profile));
});

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
        target: s.simulating ? null : s.targetWatts,
        data: s.latest,
        smoothedPower: s.smoothedPower);
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

  /// Starts a ride, or resumes a paused one; no-op while recording.
  void startOrResume() {
    switch (_recording.status) {
      case RecStatus.idle:
        start();
      case RecStatus.paused:
        resume();
      case RecStatus.recording:
    }
  }

  /// Start, pause or resume, whichever the current status calls for.
  void toggle() {
    if (_recording.status == RecStatus.recording) {
      pause();
    } else {
      startOrResume();
    }
  }

  /// First half of ending a ride: pauses, and returns what the rider must
  /// decide on. Null when nothing was recorded, in which case it has already
  /// discarded. Follow with [finish].
  StopSummary? requestStop() {
    final wasRecording = _recording.status == RecStatus.recording;
    pause();
    final samples = List.of(_recording.samples);
    if (samples.isEmpty) {
      discard();
      return null;
    }
    return StopSummary(
      stats: RideStats.of(samples,
          kcal: rideKcal(samples, ref.read(riderProfileProvider))),
      joules: rideJoules(samples),
      wasRecording: wasRecording,
    );
  }

  /// Second half: applies the rider's [choice]. Returns the export path for
  /// [StopChoice.save] (throws if saving fails, keeping the recording so the
  /// rider can retry or discard), otherwise null.
  Future<String?> finish(StopChoice choice, StopSummary summary) async {
    switch (choice) {
      case StopChoice.save:
        return save();
      case StopChoice.discard:
        discard();
      case StopChoice.keepGoing:
        if (summary.wasRecording) resume();
    }
    return null;
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
