import 'dart:async';
import 'dart:typed_data';

/// FTMS Control Point opcodes (characteristic 0x2AD9).
abstract final class FtmsOpcode {
  static const requestControl = 0x00;
  static const reset = 0x01;
  static const setTargetResistance = 0x04;
  static const setTargetPower = 0x05;
  static const startOrResume = 0x07;
  static const stopOrPause = 0x08;
  static const setIndoorBikeSimulation = 0x11;
  static const responseCode = 0x80;
}

enum FtmsResult {
  success(0x01),
  notSupported(0x02),
  invalidParameter(0x03),
  operationFailed(0x04),
  controlNotPermitted(0x05),
  unknown(-1);

  const FtmsResult(this.code);
  final int code;

  static FtmsResult fromCode(int c) =>
      values.firstWhere((r) => r.code == c, orElse: () => unknown);
}

class ControlResponse {
  const ControlResponse(this.requestOpcode, this.result);
  final int requestOpcode;
  final FtmsResult result;
  bool get success => result == FtmsResult.success;
}

class FtmsControlTimeout implements Exception {
  FtmsControlTimeout(this.opcode);
  final int opcode;
  @override
  String toString() =>
      'Trainer did not answer control command 0x${opcode.toRadixString(16)}';
}

// ---- Encoders (little-endian, per the FTMS spec) ----

Uint8List encodeRequestControl() => Uint8List.fromList([FtmsOpcode.requestControl]);

Uint8List encodeStartOrResume() => Uint8List.fromList([FtmsOpcode.startOrResume]);

/// Param 0x01 = stop, 0x02 = pause.
Uint8List encodeStop() => Uint8List.fromList([FtmsOpcode.stopOrPause, 0x01]);

Uint8List encodeSetTargetPower(int watts) {
  final bd = ByteData(3);
  bd.setUint8(0, FtmsOpcode.setTargetPower);
  bd.setInt16(1, watts.clamp(0, 4000).toInt(), Endian.little);
  return bd.buffer.asUint8List();
}

/// Units: wind 0.001 m/s, grade 0.01 %, crr 0.0001, cw 0.01 kg/m.
Uint8List encodeSimulation({
  required double gradePercent,
  double windMps = 0,
  double crr = 0.004,
  double cw = 0.51,
}) {
  final bd = ByteData(7);
  bd.setUint8(0, FtmsOpcode.setIndoorBikeSimulation);
  bd.setInt16(1, (windMps * 1000).round().clamp(-32768, 32767).toInt(), Endian.little);
  bd.setInt16(3, (gradePercent * 100).round().clamp(-32768, 32767).toInt(), Endian.little);
  bd.setUint8(5, (crr * 10000).round().clamp(0, 255).toInt());
  bd.setUint8(6, (cw * 100).round().clamp(0, 255).toInt());
  return bd.buffer.asUint8List();
}

/// Sends control commands one at a time and waits for each indication
/// response before sending the next. Firing commands concurrently is the
/// classic way to get flaky behaviour from real trainers.
class FtmsControlPoint {
  FtmsControlPoint({
    required this.write,
    this.timeout = const Duration(seconds: 3),
  });

  final Future<void> Function(Uint8List packet) write;
  final Duration timeout;

  Future<void> _tail = Future.value();
  Completer<ControlResponse>? _waiter;
  int? _pendingOpcode;

  /// Feed every Control Point indication into this.
  void onIndication(Uint8List data) {
    if (data.length < 3 || data[0] != FtmsOpcode.responseCode) return;
    final w = _waiter;
    if (w == null || w.isCompleted || data[1] != _pendingOpcode) return;
    w.complete(ControlResponse(data[1], FtmsResult.fromCode(data[2])));
  }

  Future<ControlResponse> send(Uint8List packet) {
    final done = Completer<ControlResponse>();
    _tail = _tail.then((_) => _run(packet, done));
    return done.future;
  }

  Future<void> _run(Uint8List packet, Completer<ControlResponse> done) async {
    final waiter = Completer<ControlResponse>();
    _waiter = waiter;
    _pendingOpcode = packet[0];
    try {
      await write(packet);
      final r = await waiter.future.timeout(
        timeout,
        onTimeout: () => throw FtmsControlTimeout(packet[0]),
      );
      done.complete(r);
    } catch (e, st) {
      done.completeError(e, st);
    } finally {
      _waiter = null;
      _pendingOpcode = null;
    }
  }
}
