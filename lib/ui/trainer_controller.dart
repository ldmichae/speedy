import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../devices/ble/ble_transport.dart';
import '../devices/ble/device_scanner.dart';
import '../devices/ble/universal_ble_transport.dart';
import '../devices/ble/uuids.dart';
import '../devices/ftms/ftms_trainer.dart';
import '../devices/simulated/simulated_trainer.dart';
import '../devices/trainer.dart';
import '../devices/trainer_session.dart';
import 'heart_rate_controller.dart';

final bleTransportProvider =
    Provider<BleTransport>((ref) => UniversalBleTransport());

final trainerControllerProvider =
    NotifierProvider<TrainerController, TrainerState>(TrainerController.new);

class TrainerState {
  const TrainerState({
    this.status = TrainerStatus.disconnected,
    this.deviceName,
    this.latest,
    this.smoothedPower,
    this.targetWatts = 100,
    this.gradePercent,
    this.scanning = false,
    this.scanResults = const [],
    this.error,
  });

  final TrainerStatus status;
  final String? deviceName;
  final BikeData? latest;
  final double? smoothedPower;
  final int targetWatts;

  /// Road grade while the trainer simulates a route; null in ERG mode.
  final double? gradePercent;
  bool get simulating => gradePercent != null;
  final bool scanning;
  final List<BleScanResult> scanResults;
  final String? error;

  TrainerState copyWith({
    TrainerStatus? status,
    String? deviceName,
    BikeData? latest,
    double? smoothedPower,
    int? targetWatts,
    double? gradePercent,
    bool clearGrade = false,
    bool? scanning,
    List<BleScanResult>? scanResults,
    String? error,
    bool clearError = false,
    bool clearData = false,
  }) {
    return TrainerState(
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      latest: clearData ? null : (latest ?? this.latest),
      smoothedPower: clearData ? null : (smoothedPower ?? this.smoothedPower),
      targetWatts: targetWatts ?? this.targetWatts,
      gradePercent: clearGrade ? null : (gradePercent ?? this.gradePercent),
      scanning: scanning ?? this.scanning,
      scanResults: scanResults ?? this.scanResults,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class TrainerController extends Notifier<TrainerState> {
  TrainerSession? _session;
  StreamSubscription<Reading>? _dataSub;
  StreamSubscription<TrainerStatus>? _statusSub;
  DeviceScanner? _scanner;

  DeviceScanner get _scan =>
      _scanner ??= DeviceScanner(ref.read(bleTransportProvider));

  @override
  TrainerState build() {
    ref.onDispose(() {
      _scanner?.cancel();
      unawaited(_release());
    });
    return const TrainerState();
  }

  Future<void> connectSimulated() => _connect(SimulatedTrainer());

  /// Call straight from a button press: see [DeviceScanner.start].
  Future<void> scan() async {
    state = state.copyWith(
      scanning: true,
      scanResults: const [],
      clearError: true,
    );
    try {
      await _scan.start(
        services: [ftmsService],
        onResult: (r) {
          if (state.scanResults.any((x) => x.id == r.id)) return;
          state = state.copyWith(scanResults: [...state.scanResults, r]);
          // Web's picker already is the user's choice, so connect right away.
          if (kIsWeb) connectTo(r);
        },
        onTimeout: stopScan,
      );
    } catch (e) {
      state = state.copyWith(scanning: false, error: 'Scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    await _scan.stop();
    state = state.copyWith(scanning: false);
  }

  Future<void> connectTo(BleScanResult device) async {
    await stopScan();
    await _connect(FtmsTrainer(
      transport: ref.read(bleTransportProvider),
      deviceId: device.id,
      deviceName: device.name,
    ));
  }

  Future<void> _connect(Trainer trainer) async {
    await _release();
    final session = _session = TrainerSession(trainer);
    state = state.copyWith(
      status: TrainerStatus.connecting,
      deviceName: session.name,
      clearError: true,
      clearData: true,
    );
    _statusSub = session.status.listen(_onStatus);
    _dataSub = session.readings.listen(_onReading);
    try {
      await session.connect();
      // Starts ERG at the current target so the KICKR responds right away.
      await setTarget(state.targetWatts);
    } catch (e) {
      await _release();
      state = state.copyWith(status: TrainerStatus.error, error: '$e');
    }
  }

  void _onStatus(TrainerStatus s) {
    state = state.copyWith(status: s, clearData: s == TrainerStatus.disconnected);
  }

  void _onReading(Reading r) {
    final d = r.data;
    // A connected strap beats the trainer's own heart rate pass-through.
    final strap = ref.read(heartRateControllerProvider).bpm;
    final data = strap == null
        ? d
        : BikeData(
            powerWatts: d.powerWatts,
            cadenceRpm: d.cadenceRpm,
            speedKph: d.speedKph,
            heartRate: strap,
            resistanceLevel: d.resistanceLevel,
            distanceMeters: d.distanceMeters,
            elapsedSeconds: d.elapsedSeconds,
          );
    state = state.copyWith(latest: data, smoothedPower: r.smoothedPower);
  }

  Future<void> setTarget(int watts) async {
    final w = TrainerSession.clampTarget(watts);
    state = state.copyWith(targetWatts: w, clearGrade: true); // ERG replaces SIM
    try {
      await _session?.setTarget(w);
    } catch (e) {
      state = state.copyWith(error: 'Could not set target: $e');
    }
  }

  Future<void> adjustTarget(int delta) => setTarget(state.targetWatts + delta);

  /// Simulation mode: the trainer applies road [gradePercent] as resistance.
  /// Sending an ERG target (setTarget) switches back. Callers may call this
  /// every second: a change under 0.2% from what the trainer was last told
  /// is not sent. Entering ERG clears the grade, so the next call always sends.
  Future<void> setGrade(double gradePercent) async {
    final g = TrainerSession.clampGrade(gradePercent);
    final last = state.gradePercent;
    if (last != null && (last - g).abs() < 0.2) return;
    state = state.copyWith(gradePercent: g);
    try {
      await _session?.setSimulation(g);
    } catch (e) {
      state = state.copyWith(error: 'Could not set grade: $e');
    }
  }

  Future<void> disconnect() async {
    await _release();
    state = state.copyWith(status: TrainerStatus.disconnected, clearData: true);
  }

  Future<void> _release() async {
    await _dataSub?.cancel();
    await _statusSub?.cancel();
    _dataSub = null;
    _statusSub = null;
    final s = _session;
    _session = null;
    await s?.dispose();
  }
}
