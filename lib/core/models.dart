/// One reading from a trainer. Any field is null if the device didn't send it.
class BikeData {
  const BikeData({
    this.powerWatts,
    this.cadenceRpm,
    this.speedKph,
    this.heartRate,
    this.resistanceLevel,
    this.distanceMeters,
    this.elapsedSeconds,
  });

  final int? powerWatts;
  final double? cadenceRpm;
  final double? speedKph;
  final int? heartRate;
  final int? resistanceLevel;
  final int? distanceMeters;
  final int? elapsedSeconds;

  @override
  String toString() =>
      'BikeData(power: $powerWatts W, cadence: $cadenceRpm rpm, '
      'speed: $speedKph km/h, hr: $heartRate)';
}
