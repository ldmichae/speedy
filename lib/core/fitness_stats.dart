import 'ride_record.dart';

/// Distance and climbing summed over some rides (metric).
class DayTotal {
  const DayTotal(this.km, this.gainMeters);
  final double km;
  final double gainMeters;

  static const zero = DayTotal(0, 0);
  DayTotal operator +(DayTotal o) => DayTotal(km + o.km, gainMeters + o.gainMeters);
}

/// The calendar day (local, midnight) of [t].
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Rides summed per local calendar day. Days without rides are absent.
Map<DateTime, DayTotal> dailyTotals(Iterable<RideRecord> rides) {
  final days = <DateTime, DayTotal>{};
  for (final r in rides) {
    final s = r.stats;
    final d = dayOf(r.startedAt);
    days[d] = (days[d] ?? DayTotal.zero) + DayTotal(s.distanceKm, s.elevationGainMeters);
  }
  return days;
}

/// Today and the 29 days before it, summed.
DayTotal last30Days(Map<DateTime, DayTotal> days, DateTime now) {
  final today = dayOf(now);
  final first = DateTime(today.year, today.month, today.day - 29);
  var total = DayTotal.zero;
  for (final e in days.entries) {
    if (!e.key.isBefore(first) && !e.key.isAfter(today)) total += e.value;
  }
  return total;
}
