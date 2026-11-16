import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/course.dart';
import 'package:indoor_cycling/core/ghost.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/ui/compete_controller.dart';
import 'package:indoor_cycling/ui/compete_screen.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_session.dart';
import 'package:indoor_cycling/ui/route_tile.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';

import 'fakes/in_memory_json_store.dart';

/// A trainer that is simply "connected": no timers, nothing to dispose.
class _ConnectedTrainer extends TrainerController {
  @override
  TrainerState build() =>
      const TrainerState(status: TrainerStatus.connected, deviceName: 'T');
}

void main() {
  Future<ProviderContainer> open(WidgetTester t, Widget home,
      {bool connected = false}) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ghostStoreProvider.overrideWithValue(InMemoryJsonStore()),
        if (connected) trainerControllerProvider.overrideWith(_ConnectedTrainer.new),
      ],
      child: MaterialApp(home: home),
    ));
    await t.pumpAndSettle();
    return ProviderScope.containerOf(t.element(find.byWidget(home)));
  }

  const tile = Scaffold(
      body: SizedBox(width: 400, height: 300, child: RouteMapTile()));
  final course = courseById('short-sharp-v1')!;
  Ghost sam() => Ghost(
      id: 'g',
      course: course.id,
      name: 'Sam',
      t: [0, 300],
      d: [0, course.route.lengthMeters],
      power: [250, 280],
      hr: [150, 170],
      kg: 70);

  testWidgets('the catalog lists every course and opens one', (t) async {
    await open(t, const CompeteScreen());
    expect(find.text(courses.first.name), findsOneWidget);
    await t.tap(find.text(courses.first.name));
    await t.pumpAndSettle();
    expect(find.textContaining('No ghosts yet'), findsOneWidget);
    expect(find.textContaining('Go to start line'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('lined up, nothing starts until Start race and its countdown',
      (t) async {
    final c = await open(t, tile, connected: true);
    c.read(competeProvider.notifier).stage(course, [sam()]);
    await t.pump();
    expect(find.byType(RaceView), findsOneWidget);
    expect(find.textContaining('at the start line'), findsOneWidget);
    expect(find.textContaining('to beat 05:00'), findsOneWidget);
    expect(c.read(routeRunProvider), isNull);
    expect(c.read(recorderProvider).status, RecStatus.idle); // warm up freely

    await t.tap(find.text('Start race'));
    await t.pump();
    expect(find.text('5'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    expect(find.text('1'), findsOneWidget);
    expect(c.read(routeRunProvider), isNull);

    await t.pump(const Duration(seconds: 1));
    expect(c.read(competeProvider)!.started, isTrue);
    expect(identical(c.read(routeRunProvider)!.course, course.route), isTrue);
    expect(c.read(routeRunProvider)!.simulate, isTrue);
    expect(c.read(recorderProvider).status, RecStatus.recording);
    expect(find.textContaining('to go'), findsOneWidget);
    expect(find.textContaining('ahead'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('250 W · 3.6 W/kg · 150 bpm'), findsOneWidget);
    expect(t.takeException(), isNull);

    // Stopping the route ends the race; the ride goes on.
    c.read(rideSessionProvider.notifier).stopRoute();
    await t.pump();
    expect(c.read(competeProvider), isNull);
    expect(find.byType(RaceView), findsNothing);
    c.read(recorderProvider.notifier).discard();
  });

  testWidgets('without a trainer the race cannot start', (t) async {
    final c = await open(t, tile);
    c.read(competeProvider.notifier).stage(course, [sam()]);
    await t.pump();
    expect(find.text('Connect a trainer to start'), findsOneWidget);
    expect(
        t.widget<ButtonStyleButton>(find.ancestor(
            of: find.text('Start race'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).enabled,
        isFalse);
  });

  testWidgets('leaving the line mid-countdown starts nothing', (t) async {
    final c = await open(t, tile, connected: true);
    c.read(competeProvider.notifier)
      ..stage(course, const [])
      ..startCountdown();
    await t.pump(const Duration(seconds: 2));
    await t.tap(find.byTooltip('Leave the start line'));
    await t.pump(const Duration(seconds: 5));
    expect(c.read(competeProvider), isNull);
    expect(c.read(routeRunProvider), isNull);
    expect(c.read(recorderProvider).status, RecStatus.idle);
  });
}
