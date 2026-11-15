import 'ride_recording.dart';
import 'ride_stats.dart';

/// A saved ride as kept in history: full samples (including the ERG target,
/// which FIT export drops) plus the calories computed from the rider profile
/// at the time.
class RideRecord {
  const RideRecord({
    required this.startedAt,
    required this.samples,
    this.kcal,
  });

  final DateTime startedAt;
  final List<RideSample> samples;
  final double? kcal;

  /// Also the storage key; saving the same ride twice overwrites it.
  String get id => startedAt.millisecondsSinceEpoch.toString();

  RideStats get stats => RideStats.of(samples, kcal: kcal);

  static const _version = 1;

  Map<String, Object?> toJson() => {
        'v': _version,
        'startedAt': startedAt.toIso8601String(),
        'kcal': kcal,
        // [t, target, power, smoothed, cadence, speed, hr, grade] per sample
        'samples': [
          for (final s in samples)
            [s.t, s.target, s.power, s.smoothedPower, s.cadence, s.speed, s.heartRate, s.grade]
        ],
      };

  /// Throws FormatException (or a cast error) on malformed input.
  factory RideRecord.fromJson(Map<String, Object?> j) {
    if (j['v'] != _version) throw FormatException('Unknown ride version ${j['v']}');
    return RideRecord(
      startedAt: DateTime.parse(j['startedAt']! as String),
      kcal: (j['kcal'] as num?)?.toDouble(),
      samples: [
        for (final r in (j['samples']! as List).cast<List<Object?>>())
          RideSample(
            t: (r[0]! as num).toDouble(),
            target: (r[1] as num?)?.toInt(),
            power: (r[2] as num?)?.toInt(),
            smoothedPower: (r[3] as num?)?.toDouble(),
            cadence: (r[4] as num?)?.toDouble(),
            speed: (r[5] as num?)?.toDouble(),
            heartRate: (r[6] as num?)?.toInt(),
            // Rides saved before elevation was recorded have 7 columns.
            grade: r.length > 7 ? (r[7] as num?)?.toDouble() : null,
          ),
      ],
    );
  }
}
