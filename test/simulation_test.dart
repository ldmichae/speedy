import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/plan.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/devices/simulated/simulated_trainer.dart';
import 'package:indoor_cycling/devices/trainer_session.dart';
import 'package:indoor_cycling/ui/plan_controller.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/route_controller.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:latlong2/latlong.dart';

// ~1 km north, climbing a steady 5%.
final route = SavedRoute(
  'Hill',
  const [LatLng(0, 0), LatLng(0.009, 0)],
  const [LatLng(0, 0), LatLng(0.009, 0)],
  elevation: ElevationProfile.fromSamples(
    [for (var i = 0; i <= 20; i++) i * 50.0],
    [for (var i = 0; i <= 20; i++) i * 2.5],
  ),
);

void main() {
  test('simulated speed: climbs are slower and descents faster than flat', () {
    final flat = simulatedSpeedKph(150, 0);
    expect(flat, inInclusiveRange(18, 30));
    expect(simulatedSpeedKph(150, 6), lessThan(flat / 2));
    expect(simulatedSpeedKph(150, -5), greaterThan(flat));
    expect(simulatedSpeedKph(10, 15), 1.8); // barely moving
  });

  test('grades sent to the trainer are clamped', () {
    expect(TrainerSession.clampGrade(40), 15);
    expect(TrainerSession.clampGrade(-40), -10);
  });

  test('setGrade enters simulation; an ERG target leaves it', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final t = c.read(trainerControllerProvider.notifier);
    await t.setGrade(4.2);
    expect(c.read(trainerControllerProvider).gradePercent, 4.2);
    expect(c.read(trainerControllerProvider).simulating, isTrue);
    await t.setTarget(200);
    expect(c.read(trainerControllerProvider).simulating, isFalse);
  });

  test('setGrade ignores changes under 0.2% but re-sends after ERG', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final t = c.read(trainerControllerProvider.notifier);
    await t.setGrade(4.0);
    await t.setGrade(4.1);
    expect(c.read(trainerControllerProvider).gradePercent, 4.0);
    await t.setGrade(4.3);
    expect(c.read(trainerControllerProvider).gradePercent, 4.3);
    await t.setTarget(200); // ERG clears the grade
    await t.setGrade(4.3);
    expect(c.read(trainerControllerProvider).gradePercent, 4.3);
  });

  test('a plan and a simulation never own the target together', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    const plan = Plan('p', [PlanBlock([PlanStep(60, 150)])]);
    c.read(routeRunProvider.notifier).start(route, simulate: true);
    expect(c.read(targetLockProvider), TargetLock.simulation);

    c.read(planRunProvider.notifier).start(plan, null);
    expect(c.read(targetLockProvider), TargetLock.plan);
    expect(c.read(routeRunProvider)!.simulate, isFalse);

    c.read(routeRunProvider.notifier).start(route, simulate: true);
    expect(c.read(planRunProvider), isNull);
    expect(c.read(targetLockProvider), TargetLock.simulation);
    c.read(recorderProvider.notifier).discard();
  });

  test('a simulated ride follows the route grade, locks the target, then restores ERG', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(routeRunProvider.notifier).start(route, simulate: true);

    expect(c.read(targetLockProvider), TargetLock.simulation);
    expect(c.read(trainerControllerProvider).gradePercent, closeTo(5, 0.2));

    c.read(routeRunProvider.notifier).stop();
    expect(c.read(trainerControllerProvider).simulating, isFalse);
    expect(c.read(targetLockProvider), isNull);
    c.read(recorderProvider.notifier).discard();
  });

  test('a route without elevation cannot simulate', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(routeRunProvider.notifier).start(route.withElevation(null), simulate: true);
    expect(c.read(routeRunProvider)!.simulate, isFalse);
    expect(c.read(trainerControllerProvider).simulating, isFalse);
    c.read(recorderProvider.notifier).discard();
  });

  test('a plan and a simulation take turns owning the trainer', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    const plan = Plan('P', [PlanBlock([PlanStep(600, 150)])]);

    c.read(routeRunProvider.notifier).start(route, simulate: true);
    c.read(planRunProvider.notifier).start(plan, null);
    expect(c.read(targetLockProvider), TargetLock.plan);
    expect(c.read(trainerControllerProvider).simulating, isFalse);
    expect(c.read(routeRunProvider), isNotNull); // the map carries on

    c.read(routeRunProvider.notifier).stop();
    c.read(routeRunProvider.notifier).start(route, simulate: true);
    expect(c.read(planRunProvider), isNull);
    expect(c.read(targetLockProvider), TargetLock.simulation);
    c.read(recorderProvider.notifier).discard();
  });

  test('the simulated trainer reports the physics speed in SIM mode', () async {
    final t = SimulatedTrainer();
    final speeds = <double>[];
    t.data.listen((d) => speeds.add(d.speedKph!));
    await t.connect();
    await t.setSimulation(gradePercent: 8);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await t.setSimulation(gradePercent: 0);
    final climbing = speeds.last;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(speeds.last, greaterThan(climbing));
    await t.dispose();
  });
}
