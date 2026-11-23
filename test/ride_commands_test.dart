import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/plan.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/ui/navigation.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_commands.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';

import 'simulation_test.dart' show route;

void main() {
  late ProviderContainer c;
  late RideCommands cmd;
  setUp(() {
    c = ProviderContainer();
    addTearDown(c.dispose);
    cmd = c.read(rideCommandsProvider);
  });

  int target() => c.read(trainerControllerProvider).targetWatts;
  RecStatus status() => c.read(recorderProvider).status;

  test('toggleRecording starts, pauses and resumes', () {
    cmd.toggleRecording();
    expect(status(), RecStatus.recording);
    cmd.toggleRecording();
    expect(status(), RecStatus.paused);
    cmd.toggleRecording();
    expect(status(), RecStatus.recording);
    c.read(recorderProvider.notifier).discard();
  });

  test('nudgeTarget moves the target, but not while a plan owns it', () {
    final before = target();
    cmd.nudgeTarget(5);
    expect(target(), before + 5);

    c.read(rideSessionProvider.notifier).startPlan(
        const Plan('p', [
          PlanBlock([PlanStep(60, 150)])
        ]),
        null);
    cmd.nudgeTarget(25);
    expect(target(), 150);
    c.read(recorderProvider.notifier).discard();
  });

  test('the arrows shift gears on a simulated route, else move the target',
      () async {
    int gear() => c.read(trainerControllerProvider).gear;
    final before = target();
    cmd.nudge(5);
    expect(target(), before + 5);
    expect(gear(), TrainerState.neutralGear);

    c.read(rideSessionProvider.notifier).startRoute(route, simulate: true);
    expect(c.read(targetLockProvider), TargetLock.simulation);
    await pumpEventQueue();
    cmd.nudge(25);
    cmd.nudge(5);
    cmd.nudge(-5);
    await pumpEventQueue();
    expect(gear(), TrainerState.neutralGear + 1);
    expect(target(), before + 5);
    c.read(recorderProvider.notifier).discard();
  });

  test('the keys act only on the ride page, on top', () {
    var onTop = true;
    final keys = rideShortcuts(cmd, () => onTop);
    final space = keys[const SingleActivator(LogicalKeyboardKey.space)]!;
    final up =
        keys[const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true)]!;

    c.read(pageProvider.notifier).state = AppPage.ride;
    final before = target();
    up();
    expect(target(), before + 25);

    onTop = false; // under a dialog
    space();
    expect(status(), RecStatus.idle);

    onTop = true;
    c.read(pageProvider.notifier).state = AppPage.plans;
    space();
    expect(status(), RecStatus.idle);

    c.read(pageProvider.notifier).state = AppPage.ride;
    space();
    expect(status(), RecStatus.recording);
    c.read(recorderProvider.notifier).discard();
  });

  group('ERG or Road', () {
    RideSession session() => c.read(rideSessionProvider.notifier);
    bool road() => c.read(rideSessionProvider).road;

    test('with no route the road is a flat free ride, ridden on gears', () {
      session().setRoad(true);
      expect(road(), isTrue);
      expect(c.read(rideSessionProvider).freeRide, isTrue);
      expect(c.read(targetLockProvider), TargetLock.simulation);
      final before = target();
      cmd.nudge(5); // a gear now, not watts
      expect(target(), before);

      session().setRoad(false);
      expect(road(), isFalse);
      expect(c.read(targetLockProvider), isNull);
    });

    test('a route switches between its climbs and ERG mid-ride', () {
      session().startRoute(route, simulate: true);
      expect(road(), isTrue);
      session().setRoad(false);
      expect(road(), isFalse);
      expect(c.read(routeRunProvider), isNotNull); // the ride goes on
      session().setRoad(true);
      expect(c.read(routeRunProvider)!.simulate, isTrue);
      c.read(recorderProvider.notifier).discard();
    });

    test('a plan holds ERG, and ends a free ride', () {
      session().setRoad(true);
      session().startPlan(
          const Plan('p', [
            PlanBlock([PlanStep(60, 150)])
          ]),
          null);
      expect(road(), isFalse);
      session().setRoad(true); // the plan owns the target
      expect(road(), isFalse);
      c.read(recorderProvider.notifier).discard();
    });

    test('a route with no heights stays in ERG', () {
      session().startRoute(route.withElevation(null), simulate: true);
      expect(road(), isFalse);
      session().setRoad(true);
      expect(road(), isFalse);
      c.read(recorderProvider.notifier).discard();
    });
  });
}
