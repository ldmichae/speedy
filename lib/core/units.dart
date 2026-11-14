/// Display units. Stored data (rides, profile, exports) is always metric;
/// conversion happens only where values are shown or typed in.
enum UnitSystem {
  metric('Metric'),
  imperial('Imperial');

  const UnitSystem(this.label);
  final String label;
}

const kmPerMile = 1.609344;
const kgPerPound = 0.45359237;
const cmPerInch = 2.54;

double speedIn(double kph, UnitSystem u) =>
    u == UnitSystem.imperial ? kph / kmPerMile : kph;
String speedUnit(UnitSystem u) => u == UnitSystem.imperial ? 'mph' : 'km/h';

double distanceIn(double km, UnitSystem u) =>
    u == UnitSystem.imperial ? km / kmPerMile : km;
String distanceUnit(UnitSystem u) => u == UnitSystem.imperial ? 'mi' : 'km';

const feetPerMetre = 3.280839895;

/// Elevation (metres) as "123 m" or "404 ft".
String elevationText(double m, UnitSystem u) => u == UnitSystem.imperial
    ? '${(m * feetPerMetre).round()} ft'
    : '${m.round()} m';

/// Route length (metres) as "850 m", "12.4 km", "400 ft" or "7.7 mi".
String routeDistanceText(double meters, UnitSystem u) {
  if (u == UnitSystem.imperial) {
    final mi = meters / 1000 / kmPerMile;
    return mi < 0.1
        ? '${(meters * feetPerMetre).round()} ft'
        : '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
  }
  return meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 2 : 1)} km';
}

double kgToPounds(double kg) => kg / kgPerPound;
double poundsToKg(double lb) => lb * kgPerPound;

/// Whole feet and the remaining inches, rounded to the nearest inch.
(int feet, int inches) cmToFeetInches(int cm) {
  final total = (cm / cmPerInch).round();
  return (total ~/ 12, total % 12);
}

int feetInchesToCm(int feet, num inches) =>
    ((feet * 12 + inches) * cmPerInch).round();
