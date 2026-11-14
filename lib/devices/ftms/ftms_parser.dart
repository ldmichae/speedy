import 'dart:typed_data';

import '../../core/models.dart';

/// Parses the FTMS Indoor Bike Data characteristic (0x2AD2).
///
/// Layout: uint16 flags, then optional fields in a fixed order. Bit 0 is
/// inverted: speed is present when bit 0 is CLEAR. Throws RangeError if the
/// packet is shorter than its flags claim; callers should drop such packets.
BikeData parseIndoorBikeData(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final flags = bd.getUint16(0, Endian.little);
  var o = 2;
  bool has(int bit) => flags & (1 << bit) != 0;

  double? speed;
  if (!has(0)) {
    speed = bd.getUint16(o, Endian.little) * 0.01; // km/h
    o += 2;
  }
  if (has(1)) o += 2; // average speed
  double? cadence;
  if (has(2)) {
    cadence = bd.getUint16(o, Endian.little) * 0.5; // rpm
    o += 2;
  }
  if (has(3)) o += 2; // average cadence
  int? distance;
  if (has(4)) {
    distance =
        bd.getUint8(o) | (bd.getUint8(o + 1) << 8) | (bd.getUint8(o + 2) << 16);
    o += 3;
  }
  int? resistance;
  if (has(5)) {
    resistance = bd.getInt16(o, Endian.little);
    o += 2;
  }
  int? power;
  if (has(6)) {
    power = bd.getInt16(o, Endian.little);
    o += 2;
  }
  if (has(7)) o += 2; // average power
  if (has(8)) o += 5; // total energy (2) + energy/hour (2) + energy/min (1)
  int? hr;
  if (has(9)) {
    hr = bd.getUint8(o);
    o += 1;
  }
  if (has(10)) o += 1; // metabolic equivalent
  int? elapsed;
  if (has(11)) {
    elapsed = bd.getUint16(o, Endian.little);
    o += 2;
  }

  return BikeData(
    powerWatts: power,
    cadenceRpm: cadence,
    speedKph: speed,
    heartRate: (hr == null || hr == 0) ? null : hr,
    resistanceLevel: resistance,
    distanceMeters: distance,
    elapsedSeconds: elapsed,
  );
}

/// Parses the Heart Rate Measurement characteristic (0x2A37).
/// Returns bpm, or null if the packet carries no reading.
int? parseHeartRateMeasurement(Uint8List bytes) {
  if (bytes.length < 2) return null;
  final is16Bit = bytes[0] & 0x01 != 0;
  final bpm = is16Bit
      ? ByteData.sublistView(bytes).getUint16(1, Endian.little)
      : bytes[1];
  return bpm == 0 ? null : bpm;
}
