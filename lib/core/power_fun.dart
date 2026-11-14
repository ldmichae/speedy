import 'ride_recording.dart';

/// Work done at the pedals: power × time over the ride, in joules. Samples
/// without power count as zero, as in [rideKcal].
double rideJoules(List<RideSample> samples) {
  var j = 0.0;
  for (var i = 1; i < samples.length; i++) {
    j += (samples[i].power ?? 0) * (samples[i].t - samples[i - 1].t);
  }
  return j;
}

/// "142 Wh" or "1.2 kWh".
String energyText(double joules) {
  final wh = joules / 3600;
  return wh >= 1000
      ? '${(wh / 1000).toStringAsFixed(2)} kWh'
      : '${wh.toStringAsFixed(wh < 10 ? 1 : 0)} Wh';
}

String _duration(double seconds) {
  String n(double v) => v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  if (seconds < 90) return '${seconds.round()} seconds';
  if (seconds < 5400) return '${(seconds / 60).round()} minutes';
  if (seconds < 172800) return '${n(seconds / 3600)} hours';
  return '${n(seconds / 86400)} days';
}

String _count(double v, String one, String many) {
  final n = v.round();
  return n == 1 ? '1 $one' : '$n $many';
}

// Rough, round-number household figures: this is for fun, not physics.
// A toaster is ~900 W for ~2 min per two slices; a kettle takes ~335 kJ per
// litre from tap to boil; a phone battery holds ~12 Wh; a bag of microwave
// popcorn takes ~1 kW for 3 min.
final _facts = <(double, String Function(double units), bool)>[
  // (joules per unit, text, true if the unit is a countable thing)
  (54000, (n) => 'toast ${_count(n, 'slice of bread', 'slices of bread')}', true),
  (30, (s) => 'run a desk fan for ${_duration(s)}', false),
  (43200, (n) => 'fully charge a phone ${_count(n, 'time', 'times')}', true),
  (335000, (n) => 'boil ${_count(n, 'litre', 'litres')} of water', true),
  (100, (s) => 'watch ${_duration(s)} of TV', false),
  (180000, (n) => 'pop ${_count(n, 'bag', 'bags')} of microwave popcorn', true),
  (10, (s) => 'light an LED bulb for ${_duration(s)}', false),
];

/// Up to four "enough to ..." lines for [joules]: only ones that come out
/// at one or more of the thing (or a minute or more). Never empty unless
/// there is no energy at all.
List<String> funFacts(double joules) {
  if (joules <= 0) return const [];
  final out = <String>[];
  for (final (per, text, countable) in _facts) {
    final units = joules / per;
    if (units >= (countable ? 0.5 : 60)) out.add(text(units));
    if (out.length == 4) break;
  }
  return out.isEmpty ? [_facts[1].$2(joules / 30)] : out;
}
