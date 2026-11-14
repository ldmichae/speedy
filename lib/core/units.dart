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

double kgToPounds(double kg) => kg / kgPerPound;
double poundsToKg(double lb) => lb * kgPerPound;

/// Whole feet and the remaining inches, rounded to the nearest inch.
(int feet, int inches) cmToFeetInches(int cm) {
  final total = (cm / cmPerInch).round();
  return (total ~/ 12, total % 12);
}

int feetInchesToCm(int feet, num inches) =>
    ((feet * 12 + inches) * cmPerInch).round();
