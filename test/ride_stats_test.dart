import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_record.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/ride_stats.dart';
import 'package:indoor_cycling/core/rider_profile.dart';

const male = RiderProfile(heightCm: 180, weightKg: 80, age: 30, sex: Sex.male);

void main() {
  group('RideStats', () {
    test('time, distance and average power', () {
      final stats = RideStats.of(const [
        RideSample(t: 0, power: 100, speed: 99), // first speed has no interval
        RideSample(t: 50, power: 200, speed: 36),
        RideSample(t: 100, speed: 36), // coasting: no power
      ]);
      expect(stats.duration, const Duration(seconds: 100));
      expect(stats.distanceMeters, closeTo(1000, 0.001)); // 10 m/s for 100 s
      expect(stats.distanceKm, closeTo(1.0, 1e-6));
      expect(stats.avgPower, 150);
      expect(stats.kcal, isNull);
    });

    test('an empty ride is all zeros', () {
      final stats = RideStats.of(const []);
      expect(stats.duration, Duration.zero);
      expect(stats.distanceMeters, 0);
      expect(stats.avgPower, isNull);
    });
  });

  group('rideKcal', () {
    // One hour at a steady 200 W.
    const hour = [RideSample(t: 0, power: 200), RideSample(t: 3600, power: 200)];

    test('work cost plus resting metabolism', () {
      // 720 kJ / 0.24 / 4.184 = 717.0 kcal; BMR 1780 kcal/day -> 74.2 for 1 h.
      expect(rideKcal(hour, male), closeTo(791.2, 0.5));
    });

    test('sex changes the resting term only', () {
      final female = male.copyWith(sex: Sex.female);
      // BMR is 166 kcal/day lower -> 6.9 kcal lower over one hour.
      expect(rideKcal(hour, male)! - rideKcal(hour, female)!, closeTo(6.9, 0.1));
    });

    test('a heavier rider burns more at rest, same work cost', () {
      final heavy = male.copyWith(weightKg: 100);
      expect(rideKcal(hour, heavy)! - rideKcal(hour, male)!, closeTo(8.3, 0.1));
    });

    test('coasting costs only resting metabolism', () {
      const coast = [RideSample(t: 0), RideSample(t: 3600)];
      expect(rideKcal(coast, male), closeTo(74.2, 0.1));
    });

    test('null until the profile is complete', () {
      expect(rideKcal(hour, const RiderProfile()), isNull);
      expect(
          rideKcal(hour, const RiderProfile(heightCm: 180, weightKg: 80, age: 30)),
          isNull);
      expect(rideKcal(const [], male), isNull);
    });
  });

  group('RideRecord', () {
    test('JSON round-trips, including missing values', () {
      final record = RideRecord(
        startedAt: DateTime.utc(2026, 11, 13, 14, 5),
        kcal: 321.5,
        samples: const [
          RideSample(
              t: 0,
              target: 150,
              power: 148,
              smoothedPower: 147.5,
              cadence: 90.5,
              speed: 30.2,
              heartRate: 140),
          RideSample(t: 1, target: 150),
        ],
      );

      final back =
          RideRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>);

      expect(back.startedAt, record.startedAt);
      expect(back.kcal, 321.5);
      expect(back.id, record.id);
      expect(back.samples, hasLength(2));
      expect(back.samples[0].cadence, 90.5);
      expect(back.samples[0].heartRate, 140);
      expect(back.samples[1].power, isNull);
      expect(back.samples[1].target, 150);
      expect(back.stats.kcal, 321.5);
    });

    test('an unknown version is rejected', () {
      expect(
        () => RideRecord.fromJson({'v': 99, 'startedAt': '2026-01-01', 'samples': []}),
        throwsFormatException,
      );
    });
  });
}
