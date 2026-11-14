enum Sex {
  female('Female'),
  male('Male');

  const Sex(this.label);
  final String label;
}

/// Who is riding, in metric units. Any field may be unset; calories are only
/// estimated once the profile is [complete].
class RiderProfile {
  const RiderProfile({this.heightCm, this.weightKg, this.age, this.sex});

  final int? heightCm;
  final double? weightKg;
  final int? age;
  final Sex? sex;

  bool get complete =>
      heightCm != null && weightKg != null && age != null && sex != null;

  /// Accepted ranges, enforced by the preferences form.
  static const heightRange = (100, 250);
  static const weightRange = (30, 250);
  static const ageRange = (10, 100);

  RiderProfile copyWith({
    int? heightCm,
    double? weightKg,
    int? age,
    Sex? sex,
    bool clearHeight = false,
    bool clearWeight = false,
    bool clearAge = false,
  }) =>
      RiderProfile(
        heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
        age: clearAge ? null : (age ?? this.age),
        sex: sex ?? this.sex,
      );
}
