import 'ride_recording.dart';
import 'rider_profile.dart';

/// Headline numbers for a ride, shared by the live panel, history list and
/// detail view.
class RideStats {
  const RideStats({
    required this.duration,
    required this.distanceMeters,
    required this.avgPower,
    required this.kcal,
  });

  /// Moving time (paused time excluded).
  final Duration duration;
  final double distanceMeters;
  final double? avgPower;

  /// Null when no complete rider profile was available.
  final double? kcal;

  double get distanceKm => distanceMeters / 1000;

  /// [kcal] is passed in because it depends on the profile at the time.
  factory RideStats.of(List<RideSample> samples, {double? kcal}) {
    var meters = 0.0;
    var powerSum = 0;
    var powerCount = 0;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      if (s.power != null) {
        powerSum += s.power!;
        powerCount++;
      }
      if (i > 0 && s.speed != null) {
        meters += s.speed! / 3.6 * (s.t - samples[i - 1].t);
      }
    }
    return RideStats(
      duration: Duration(
          milliseconds: samples.isEmpty ? 0 : (samples.last.t * 1000).round()),
      distanceMeters: meters,
      avgPower: powerCount == 0 ? null : powerSum / powerCount,
      kcal: kcal,
    );
  }
}

/// Fraction of metabolic energy that becomes pedalling work (gross cycling
/// efficiency, typically 20-25%).
const _cyclingEfficiency = 0.24;
const _kcalPerKj = 1 / 4.184;

/// Estimated energy for a ride: the cost of the pedalling work, plus the
/// resting metabolism (Mifflin-St Jeor) for the same time. Null until the
/// profile is [RiderProfile.complete]. An estimate, not a measurement.
double? rideKcal(List<RideSample> samples, RiderProfile profile) {
  if (!profile.complete || samples.isEmpty) return null;

  var workJoules = 0.0;
  for (var i = 1; i < samples.length; i++) {
    workJoules += (samples[i].power ?? 0) * (samples[i].t - samples[i - 1].t);
  }
  final seconds = samples.last.t;

  final bmrPerDay = 10 * profile.weightKg! +
      6.25 * profile.heightCm! -
      5 * profile.age! +
      (profile.sex == Sex.male ? 5 : -161);

  return bmrPerDay / 86400 * seconds +
      workJoules / 1000 / _cyclingEfficiency * _kcalPerKj;
}
