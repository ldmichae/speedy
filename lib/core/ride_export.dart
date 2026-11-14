import 'dart:convert';
import 'dart:typed_data';

import 'ride_recording.dart';
import 'ride_storage.dart';

/// Encodes [samples] in this format and saves them; returns the file path.
Future<String> exportRide(
        List<RideSample> samples, DateTime startedAt, RideFormat format) =>
    saveRideFile(format.encode(samples, startedAt), format.ext, startedAt);

enum RideFormat {
  csv('CSV', 'csv'),
  fit('FIT', 'fit');

  const RideFormat(this.label, this.ext);
  final String label;
  final String ext;

  Uint8List encode(List<RideSample> samples, DateTime start) => switch (this) {
        RideFormat.csv => Uint8List.fromList(utf8.encode(ridesToCsv(samples))),
        RideFormat.fit => ridesToFit(samples, start),
      };
}

/// Minimal FIT activity: file_id, one record per sample, session, activity.
/// Target power has no standard FIT record field, so it is CSV-only.
Uint8List ridesToFit(List<RideSample> samples, DateTime start) {
  const e = 0x00, u8 = 0x02, u16 = 0x84, u32 = 0x86; // base types
  final b = BytesBuilder();
  void w8(int v) => b.addByte(v);
  void w16(int v) {
    w8(v & 0xFF);
    w8((v >> 8) & 0xFF);
  }

  void w32(int v) {
    w16(v & 0xFFFF);
    w16((v >> 16) & 0xFFFF);
  }

  void def(int local, int msg, List<(int, int, int)> fields) {
    w8(0x40 | local);
    w8(0);
    w8(0); // little endian
    w16(msg);
    w8(fields.length);
    for (final (n, size, type) in fields) {
      w8(n);
      w8(size);
      w8(type);
    }
  }

  // FIT epoch is 1989-12-31 UTC.
  final startFit = start.millisecondsSinceEpoch ~/ 1000 - 631065600;
  final elapsedS = samples.isEmpty ? 0.0 : samples.last.t;
  final endFit = startFit + elapsedS.round();
  final elapsedMs = (elapsedS * 1000).round();
  int clamp8(num? v) => v == null ? 0xFF : v.round().clamp(0, 254);
  int clamp16(num? v) => v == null ? 0xFFFF : v.round().clamp(0, 0xFFFE);

  def(0, 0, [(0, 1, e), (1, 2, u16), (2, 2, u16), (4, 4, u32)]);
  w8(0);
  w8(4); // activity
  w16(255); // manufacturer: development
  w16(0);
  w32(startFit);

  def(1, 20, [(253, 4, u32), (3, 1, u8), (4, 1, u8), (6, 2, u16), (7, 2, u16)]);
  for (final s in samples) {
    w8(1);
    w32(startFit + s.t.round());
    w8(clamp8(s.heartRate));
    w8(clamp8(s.cadence));
    w16(clamp16(s.speed == null ? null : s.speed! / 3.6 * 1000)); // m/s * 1000
    w16(clamp16(s.power));
  }

  def(2, 18, [(253, 4, u32), (2, 4, u32), (7, 4, u32), (8, 4, u32), (5, 1, e), (6, 1, e)]);
  w8(2);
  w32(endFit);
  w32(startFit);
  w32(elapsedMs);
  w32(elapsedMs);
  w8(2); // cycling
  w8(6); // indoor cycling

  def(3, 34, [(253, 4, u32), (0, 4, u32), (1, 2, u16), (2, 1, e), (3, 1, e), (4, 1, e)]);
  w8(3);
  w32(endFit);
  w32(elapsedMs);
  w16(1);
  w8(0); // manual
  w8(26); // activity
  w8(1); // stop

  final data = b.takeBytes();
  final header = BytesBuilder();
  void h16(int v) => header..addByte(v & 0xFF)..addByte((v >> 8) & 0xFF);
  header
    ..addByte(14)
    ..addByte(0x20);
  h16(2132);
  h16(data.length & 0xFFFF);
  h16(data.length >> 16);
  header.add('.FIT'.codeUnits);
  final head = header.toBytes();
  h16(_fitCrc(head));

  final out = BytesBuilder()
    ..add(header.takeBytes())
    ..add(data);
  final body = out.toBytes();
  final crc = _fitCrc(body);
  return Uint8List.fromList([...body, crc & 0xFF, crc >> 8]);
}

int _fitCrc(List<int> bytes) {
  const t = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];
  var crc = 0;
  for (final byte in bytes) {
    crc = ((crc >> 4) & 0x0FFF) ^ t[crc & 0xF] ^ t[byte & 0xF];
    crc = ((crc >> 4) & 0x0FFF) ^ t[crc & 0xF] ^ t[(byte >> 4) & 0xF];
  }
  return crc;
}

String ridesToCsv(List<RideSample> samples) {
  final b = StringBuffer(
      'time_s,target_w,power_w,power_3s_w,cadence_rpm,speed_kph,heart_rate_bpm\n');
  String f(num? v, [int digits = 0]) => v == null ? '' : v.toStringAsFixed(digits);
  for (final s in samples) {
    b.writeln([
      f(s.t, 1),
      f(s.target),
      f(s.power),
      f(s.smoothedPower, 1),
      f(s.cadence, 1),
      f(s.speed, 1),
      f(s.heartRate),
    ].join(','));
  }
  return b.toString();
}
