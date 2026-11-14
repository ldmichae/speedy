import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/plan.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/ui/plan_controller.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 2 s at 100, then 2 repeats of (2 s ramp 100->200).
  const plan = Plan('Test', [
    PlanBlock([PlanStep(2, 100)]),
    PlanBlock([PlanStep(2, 100, 200)], repeat: 2),
  ]);

  test('expand unrolls repeats; wattsAt ramps and ends', () {
    final s = plan.expand();
    expect(s.length, 3);
    expect(plan.totalSeconds, 6);
    expect([for (var t = 0; t < 7; t++) s.wattsAt(t)],
        [100, 100, 100, 150, 100, 150, null]);
    expect(s.indexAt(3), 1);
    expect(s.endOf(1), 4);
    expect(s.outline(10).first, (10.0, 100.0));
    expect(s.outline(10).last, (16.0, 200.0));
  });

  test('percent plans resolve against FTP', () {
    const p = Plan('P', [
      PlanBlock([PlanStep(60, 50, 100)])
    ], percent: true);
    final s = p.resolve(250).single;
    expect((s.from, s.to), (125, 250));
  });

  test('json round-trips, reads the old flat format, rejects junk', () {
    final back = Plan.fromJson(plan.toJson())!;
    expect(back.blocks[1].repeat, 2);
    expect(back.blocks[1].steps.single.to, 200);
    final old = Plan.fromJson({
      'name': 'o',
      'steps': [
        {'s': 5, 'w': 120}
      ]
    })!;
    expect(old.expand().single.from, 120);
    expect(Plan.fromJson({'name': 'x', 'blocks': []}), isNull);
    expect(
        Plan.fromJson({
          'name': 'x',
          'steps': [
            {'s': 0, 'w': 1}
          ]
        }),
        isNull);
    expect(Plan.fromJson('nope'), isNull);
  });

  test('plans and FTP persist', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(plansProvider.notifier).save(plan);
    c.read(ftpProvider.notifier).set(250);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(plansProvider);
    c2.read(ftpProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(plansProvider).single.name, 'Test');
    expect(c2.read(ftpProvider), 250);
  });

  test('start records, skip moves on, pause holds, end leaves the ride', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final run = c.read(planRunProvider.notifier);
    int target() => c.read(trainerControllerProvider).targetWatts;
    RecStatus rec() => c.read(recorderProvider).status;

    run.start(plan, null);
    expect(rec(), RecStatus.recording);
    expect(target(), 100);

    run.skip(); // into the first ramp
    expect(c.read(planRunProvider)!.step, 1);
    expect(target(), 100);

    c.read(recorderProvider.notifier).pause();
    run.skip(); // paused: position moves, target is held
    expect(c.read(planRunProvider)!.step, 2);
    expect(target(), 100);
    c.read(recorderProvider.notifier).resume();
    expect(target(), 100); // step 2 starts at 100

    run.skip();
    expect(c.read(planRunProvider), isNull);
    expect(rec(), RecStatus.recording);

    c.read(recorderProvider.notifier).discard();
  });

  test('ending the recording stops the plan', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(planRunProvider.notifier).start(plan, null);
    c.read(recorderProvider.notifier).discard();
    expect(c.read(planRunProvider), isNull);
  });
}
