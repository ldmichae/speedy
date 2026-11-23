import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

double _smooth(double from, double to, double v) {
  final t = ((v - from) / (to - from)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Vector3 _mix(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

/// The sky and sunlight at a time of day: blue noon, orange dusk, dark night.
/// shortcut: the sun rises at 6 and sets at 18 every day, everywhere; no
/// seasons or latitude. Use a solar-position formula if riders notice.
class Daylight {
  Daylight._(this.sunHeight, this.toSun);

  /// The daylight at [time]'s hour on the device clock.
  factory Daylight.at(DateTime time) {
    final hour = time.hour + time.minute / 60 + time.second / 3600;
    final a = (hour - 6) / 12 * math.pi; // 0 at sunrise, pi at sunset
    // Rises in the east (+x), crosses high in the south (-z), sets west.
    return Daylight._(math.sin(a),
        Vector3(math.cos(a), math.sin(a) * 0.9, -0.4)..normalize());
  }

  /// -1 at midnight, 0 at sunrise and sunset, 1 at noon.
  final double sunHeight;

  /// Unit vector towards the sun.
  final Vector3 toSun;

  double get _day => _smooth(-0.05, 0.35, sunHeight);
  double get _dusk => _smooth(-0.3, 0, sunHeight) * (1 - _day);

  static final _dayHorizon = Vector3(0.55, 0.70, 0.88),
      _dayZenith = Vector3(0.12, 0.32, 0.70),
      _duskHorizon = Vector3(0.80, 0.42, 0.22),
      _duskZenith = Vector3(0.10, 0.14, 0.35),
      _nightHorizon = Vector3(0.02, 0.03, 0.06),
      _nightZenith = Vector3(0.004, 0.008, 0.025);

  Vector3 _sky(Vector3 night, Vector3 dusk, Vector3 day) =>
      _mix(_mix(night, dusk, _dusk), day, _day);

  /// Linear RGB of the sky at the horizon, also the fog.
  Vector3 get horizon => _sky(_nightHorizon, _duskHorizon, _dayHorizon);

  /// Linear RGB of the sky straight up.
  Vector3 get zenith => _sky(_nightZenith, _duskZenith, _dayZenith);

  /// The way the light travels: from the sun by day, from a moon high in the
  /// south by night, so the road still shows.
  Vector3 get lightDirection =>
      sunHeight > 0 ? -toSun : Vector3(-0.4, -1, -0.3);

  /// Linear RGB of the light: warm low sun, white noon, blue moon.
  Vector3 get lightColor => sunHeight > 0
      ? _mix(Vector3(1, 0.55, 0.3), Vector3(1, 1, 1), _day)
      : Vector3(0.6, 0.7, 1);

  /// Strength of the light, 3 at noon.
  double get lightIntensity =>
      sunHeight > 0 ? 0.4 + 2.6 * _smooth(0, 0.35, sunHeight) : 0.35;

  /// Scales the ambient light, so night is dark but not black.
  double get ambient => 0.12 + 0.88 * math.max(_day, _dusk * 0.6);
}
