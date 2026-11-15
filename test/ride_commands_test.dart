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
        const Plan('p', [PlanBlock([PlanStep(60, 150)])]), null);
    cmd.nudgeTarget(25);
    expect(target(), 150);
    c.read(recorderProvider.notifier).discard();
  });

  test('the keys act only on the ride page, on top', () {
    var onTop = true;
    final keys = rideShortcuts(cmd, () => onTop);
    final space = keys[const SingleActivator(LogicalKeyboardKey.space)]!;
    final up = keys[const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true)]!;

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
}
