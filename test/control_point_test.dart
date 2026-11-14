import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/devices/ftms/control_point.dart';

void main() {
  group('encoders', () {
    test('request control and start', () {
      expect(encodeRequestControl(), [0x00]);
      expect(encodeStartOrResume(), [0x07]);
    });

    test('set target power is sint16 little-endian', () {
      expect(encodeSetTargetPower(250), [0x05, 0xFA, 0x00]);
      expect(encodeSetTargetPower(300), [0x05, 0x2C, 0x01]);
    });

    test('target power is clamped to a sane range', () {
      expect(encodeSetTargetPower(-50), [0x05, 0x00, 0x00]);
    });

    test('simulation parameters use spec units', () {
      // wind 0, grade 5.00% (500 = 0x01F4), crr 0.0040 (40), cw 0.51 (51)
      expect(
        encodeSimulation(gradePercent: 5.0),
        [0x11, 0x00, 0x00, 0xF4, 0x01, 0x28, 0x33],
      );
    });

    test('negative grade is two\'s complement', () {
      // -2.00% = -200 = 0xFF38
      expect(encodeSimulation(gradePercent: -2.0).sublist(3, 5), [0x38, 0xFF]);
    });
  });

  group('FtmsControlPoint', () {
    test('runs queued commands one at a time, in order', () async {
      final log = <int>[];
      var inFlight = 0;
      var maxInFlight = 0;
      late FtmsControlPoint cp;
      cp = FtmsControlPoint(write: (bytes) async {
        log.add(bytes[0]);
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        scheduleMicrotask(() {
          inFlight--;
          cp.onIndication(Uint8List.fromList([0x80, bytes[0], 0x01]));
        });
      });

      final results = await Future.wait([
        cp.send(encodeRequestControl()),
        cp.send(encodeStartOrResume()),
        cp.send(encodeSetTargetPower(200)),
      ]);

      expect(log, [0x00, 0x07, 0x05]);
      expect(maxInFlight, 1);
      expect(results.every((r) => r.success), isTrue);
    });

    test('surfaces error result codes', () async {
      late FtmsControlPoint cp;
      cp = FtmsControlPoint(write: (bytes) async {
        scheduleMicrotask(
            () => cp.onIndication(Uint8List.fromList([0x80, bytes[0], 0x05])));
      });
      final r = await cp.send(encodeSetTargetPower(150));
      expect(r.success, isFalse);
      expect(r.result, FtmsResult.controlNotPermitted);
    });

    test('ignores responses for a different opcode', () async {
      late FtmsControlPoint cp;
      cp = FtmsControlPoint(write: (bytes) async {
        scheduleMicrotask(() {
          cp.onIndication(Uint8List.fromList([0x80, 0x99, 0x02])); // stray
          cp.onIndication(Uint8List.fromList([0x80, bytes[0], 0x01]));
        });
      });
      final r = await cp.send(encodeRequestControl());
      expect(r.result, FtmsResult.success);
    });

    test('times out when the trainer never answers, then keeps working', () async {
      var answer = false;
      late FtmsControlPoint cp;
      cp = FtmsControlPoint(
        timeout: const Duration(milliseconds: 50),
        write: (bytes) async {
          if (answer) {
            scheduleMicrotask(() =>
                cp.onIndication(Uint8List.fromList([0x80, bytes[0], 0x01])));
          }
        },
      );
      await expectLater(
        cp.send(encodeRequestControl()),
        throwsA(isA<FtmsControlTimeout>()),
      );
      answer = true;
      final r = await cp.send(encodeStartOrResume());
      expect(r.success, isTrue);
    });
  });
}
