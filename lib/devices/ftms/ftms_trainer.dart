import 'dart:async';
import 'dart:typed_data';

import '../../core/models.dart';
import '../ble/ble_transport.dart';
import '../ble/uuids.dart';
import '../trainer.dart';
import 'control_point.dart';
import 'ftms_parser.dart';

/// A trainer that speaks the standard Fitness Machine Service (KICKR Core,
/// KICKR, KICKR Bike and most other modern smart trainers).
class FtmsTrainer implements Trainer {
  FtmsTrainer({
    required this.transport,
    required this.deviceId,
    required String deviceName,
  }) : _name = deviceName {
    _controlPoint = FtmsControlPoint(
      write: (bytes) =>
          transport.write(deviceId, ftmsService, ftmsControlPointChar, bytes),
    );
  }

  final BleTransport transport;
  final String deviceId;
  final String _name;
  late final FtmsControlPoint _controlPoint;

  final _data = StreamController<BikeData>.broadcast();
  final _status = StreamController<TrainerStatus>.broadcast();
  StreamSubscription<Uint8List>? _bikeSub;
  StreamSubscription<Uint8List>? _cpSub;
  StreamSubscription<bool>? _connSub;
  bool _disposed = false;

  @override
  String get name => _name;
  @override
  Stream<TrainerStatus> get status => _status.stream;
  @override
  Stream<BikeData> get data => _data.stream;

  @override
  Future<void> connect() async {
    _status.add(TrainerStatus.connecting);
    await transport.connect(deviceId);

    final services = await transport.discoverServices(deviceId);
    if (!services.contains(ftmsService)) {
      await transport.disconnect(deviceId);
      throw StateError('This device does not expose the Fitness Machine Service.');
    }

    _connSub = transport.connectionChanges(deviceId).listen((connected) {
      if (!connected && !_disposed) _status.add(TrainerStatus.disconnected);
    });

    // Control point first: its indications carry the replies to our commands.
    _cpSub = (await transport.subscribe(
      deviceId,
      ftmsService,
      ftmsControlPointChar,
      indicate: true,
    ))
        .listen(_controlPoint.onIndication);

    _bikeSub = (await transport.subscribe(
      deviceId,
      ftmsService,
      indoorBikeDataChar,
    ))
        .listen(_onBikeData);

    await _requestControl();
    _status.add(TrainerStatus.connected);
  }

  void _onBikeData(Uint8List bytes) {
    try {
      _data.add(parseIndoorBikeData(bytes));
    } on RangeError {
      // Truncated packet: drop it.
    }
  }

  Future<void> _requestControl() async {
    final r = await _controlPoint.send(encodeRequestControl());
    if (!r.success) {
      throw StateError(
        'Trainer refused control (${r.result.name}). '
        'Close the Wahoo/Zwift/other apps connected to it and try again.',
      );
    }
    final s = await _controlPoint.send(encodeStartOrResume());
    if (!s.success) {
      throw StateError('Trainer would not start (${s.result.name}).');
    }
  }

  @override
  Future<void> setTargetPower(int watts) async {
    var r = await _controlPoint.send(encodeSetTargetPower(watts));
    if (r.result == FtmsResult.controlNotPermitted) {
      await _requestControl();
      r = await _controlPoint.send(encodeSetTargetPower(watts));
    }
    if (!r.success) {
      throw StateError('Set target power failed (${r.result.name}).');
    }
  }

  @override
  Future<void> setSimulation({
    required double gradePercent,
    double windMps = 0,
    double crr = 0.004,
    double cw = 0.51,
  }) async {
    final r = await _controlPoint.send(encodeSimulation(
      gradePercent: gradePercent,
      windMps: windMps,
      crr: crr,
      cw: cw,
    ));
    if (!r.success) {
      throw StateError('Set simulation failed (${r.result.name}).');
    }
  }

  @override
  Future<void> disconnect() async {
    await transport.disconnect(deviceId);
    if (!_disposed) _status.add(TrainerStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _bikeSub?.cancel();
    await _cpSub?.cancel();
    await _connSub?.cancel();
    try {
      await transport.disconnect(deviceId);
    } catch (_) {}
    await _data.close();
    await _status.close();
  }
}
