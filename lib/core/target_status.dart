import 'dart:math' as math;

/// How measured power compares with the ERG target.
enum TargetStatus { onTarget, below, above }

/// Within this of the target counts as on target: 5 W, or 3% of the target
/// when that is larger (so a 300 W interval is not held to 5 W).
double targetTolerance(int target) => math.max(5, target * 0.03);

/// Watts above (positive) or below (negative) the target, rounded.
int targetDelta(double power, int target) => (power - target).round();

TargetStatus targetStatus(double power, int target) {
  final delta = power - target;
  if (delta.abs() <= targetTolerance(target)) return TargetStatus.onTarget;
  return delta > 0 ? TargetStatus.above : TargetStatus.below;
}
