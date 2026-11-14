import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/devices/ftms/ftms_parser.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  group('parseIndoorBikeData', () {
    test('speed + cadence + power', () {
      // flags 0x0044: bit0 clear (speed present), bit2 cadence, bit6 power
      final d = parseIndoorBikeData(
          b([0x44, 0x00, 0xC4, 0x09, 0xB4, 0x00, 0xC8, 0x00]));
      expect(d.speedKph, closeTo(25.0, 0.001));
      expect(d.cadenceRpm, closeTo(90.0, 0.001));
      expect(d.powerWatts, 200);
      expect(d.heartRate, isNull);
    });

    test('power + heart rate', () {
      // flags 0x0240: speed present, bit6 power, bit9 heart rate
      final d = parseIndoorBikeData(
          b([0x40, 0x02, 0xB8, 0x0B, 0x96, 0x00, 0x8E]));
      expect(d.speedKph, closeTo(30.0, 0.001));
      expect(d.powerWatts, 150);
      expect(d.heartRate, 142);
    });

    test('skips the 5-byte energy block before heart rate', () {
      // flags 0x0340: power, expended energy, heart rate
      final d = parseIndoorBikeData(b([
        0x40, 0x03, 0x00, 0x00, 0x64, 0x00,
        0x0A, 0x00, 0x3C, 0x00, 0x01, 0x78,
      ]));
      expect(d.powerWatts, 100);
      expect(d.heartRate, 120);
    });

    test('bit0 set means speed is absent', () {
      // flags 0x0041: bit0 set, bit6 power
      final d = parseIndoorBikeData(b([0x41, 0x00, 0x64, 0x00]));
      expect(d.speedKph, isNull);
      expect(d.powerWatts, 100);
    });

    test('truncated packet throws RangeError', () {
      expect(() => parseIndoorBikeData(b([0x44, 0x00, 0xC4])),
          throwsA(isA<RangeError>()));
    });
  });

  group('parseHeartRateMeasurement', () {
    test('8-bit', () => expect(parseHeartRateMeasurement(b([0x00, 72])), 72));
    test('16-bit',
        () => expect(parseHeartRateMeasurement(b([0x01, 0x90, 0x00])), 144));
    test('zero means no reading',
        () => expect(parseHeartRateMeasurement(b([0x00, 0])), isNull));
  });
}
