import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/ui/dashboard_view.dart';
import 'package:indoor_cycling/ui/metric_tile.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/recording_panel.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/in_memory_ble_transport.dart';

/// A dashboard on a connected simulated trainer. The trainer runs on real
/// timers, so it is brought up outside the test's fake clock.
Future<ProviderContainer> openDashboard(WidgetTester tester,
    {Size size = const Size(900, 2200)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    bleTransportProvider.overrideWithValue(InMemoryBleTransport()),
  ]);
  addTearDown(container.dispose);
  final trainer = container.read(trainerControllerProvider.notifier);

  await tester.runAsync(() async {
    await trainer.connectSimulated();
    for (var i = 0; i < 100; i++) {
      final s = container.read(trainerControllerProvider);
      if (s.status == TrainerStatus.connected && s.latest != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  addTearDown(() => tester.runAsync(trainer.disconnect));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: DashboardView())),
  ));
  return container;
}

double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  testWidgets('before recording: controls and live numbers, no stats or chart',
      (tester) async {
    await openDashboard(tester);

    expect(find.text('Ready to ride'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Cadence'), findsOneWidget); // live tiles are there
    expect(find.text('ERG target'), findsOneWidget);

    expect(find.byType(WorkoutSummary), findsNothing);
    expect(find.byType(RideChart), findsNothing);
    expect(find.text('Distance'), findsNothing);
  });

  testWidgets('recording adds totals incl. distance and the chart',
      (tester) async {
    final c = await openDashboard(tester);

    await tester.tap(find.text('Record'));
    await tester.pump();

    expect(c.read(recorderProvider).status, RecStatus.recording);
    expect(find.byType(WorkoutSummary), findsOneWidget);
    expect(find.byType(RideChart), findsOneWidget);
    for (final label in ['Time', 'Distance', 'Avg power', 'Energy']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Pause'), findsOneWidget);

    c.read(recorderProvider.notifier).discard(); // stop the recording timer
    await tester.pump();
  });

  testWidgets('controls, live tiles and chart read top to bottom as one workout',
      (tester) async {
    final c = await openDashboard(tester);
    await tester.tap(find.text('Record'));
    await tester.pump();

    final bar = top(tester, find.byType(WorkoutBar));
    final tiles = top(tester, find.byType(MetricTile).first);
    final summary = top(tester, find.byType(WorkoutSummary));
    final erg = top(tester, find.text('100 W')); // the ERG card's target
    expect(bar, lessThan(tiles));
    expect(tiles, lessThan(summary));
    expect(summary, lessThan(erg));

    c.read(recorderProvider.notifier).discard();
    await tester.pump();
  });

  testWidgets('the bar, live tiles and summary share one width and left edge',
      (tester) async {
    final c = await openDashboard(tester);
    await tester.tap(find.text('Record'));
    await tester.pump();

    final bar = tester.getRect(find.byType(WorkoutBar));
    final hero = tester.getRect(find.byType(MetricTile).first);
    final summary = tester.getRect(find.byType(WorkoutSummary));
    final erg = tester.getRect(
        find.ancestor(of: find.text('100 W'), matching: find.byType(Card)).first);

    for (final r in [hero, summary]) {
      expect(r.left, bar.left);
      expect(r.width, bar.width);
    }
    // The ERG card sits outside the workout outline (12 padding + 1.5 border
    // each side), flush with the outline itself.
    expect(erg.left, bar.left - 13.5);
    expect(erg.width, bar.width + 27);
    // The three small tiles together span the same width as the hero tile.
    final small = [
      for (var i = 1; i <= 3; i++) tester.getRect(find.byType(MetricTile).at(i))
    ];
    expect(small.first.left, hero.left);
    expect(small.last.right, closeTo(hero.right, 0.5));

    c.read(recorderProvider.notifier).discard();
    await tester.pump();
  });

  testWidgets('the Record bar does not move when recording starts',
      (tester) async {
    final c = await openDashboard(tester);
    final before = top(tester, find.byType(WorkoutBar));

    await tester.tap(find.text('Record'));
    await tester.pump();

    // The outline adds a little padding; nothing jumps by more than that.
    expect((top(tester, find.byType(WorkoutBar)) - before).abs(), lessThan(16));

    c.read(recorderProvider.notifier).discard();
    await tester.pump();
  });

  testWidgets('discarding a ride takes the stats and chart away again',
      (tester) async {
    final c = await openDashboard(tester);
    await tester.tap(find.text('Record'));
    await tester.pump();

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('End ride?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(c.read(recorderProvider).status, RecStatus.idle);
    expect(find.byType(RideChart), findsNothing);
    expect(find.byType(WorkoutSummary), findsNothing);
    expect(find.text('Ready to ride'), findsOneWidget);
  });

  testWidgets('pausing keeps the stats and chart on screen', (tester) async {
    final c = await openDashboard(tester);
    await tester.tap(find.text('Record'));
    await tester.pump();

    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(c.read(recorderProvider).status, RecStatus.paused);
    expect(find.byType(RideChart), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    c.read(recorderProvider.notifier).discard();
    await tester.pump();
  });

  group('wide (desktop landscape) layout', () {
    const desktop = Size(1400, 900);

    testWidgets('live tiles and the ERG target sit left, the summary right',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await tester.tap(find.text('Record'));
      await tester.pump();

      final tile = tester.getRect(find.byType(MetricTile).first);
      final summary = tester.getRect(find.byType(WorkoutSummary));
      final erg = tester.getTopLeft(find.text('100 W'));

      expect(summary.left, greaterThan(tile.right)); // beside, not below
      expect((summary.top - tile.top).abs(), lessThan(40)); // top-aligned
      expect(erg.dy, greaterThan(tile.bottom)); // ERG under the tiles
      expect(erg.dx, lessThan(summary.left)); // in the left column
      expect(tester.takeException(), isNull);

      c.read(recorderProvider.notifier).discard();
      await tester.pump();
    });

    testWidgets('both columns are aligned and the left one is one width',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await tester.tap(find.text('Record'));
      await tester.pump();

      final bar = tester.getRect(find.byType(WorkoutBar));
      final hero = tester.getRect(find.byType(MetricTile).first);
      final erg = tester.getRect(
          find.ancestor(of: find.text('100 W'), matching: find.byType(Card)).first);
      final summary = tester.getRect(find.byType(WorkoutSummary));

      expect(hero.left, bar.left); // left column starts at the bar's edge
      expect(erg.left, hero.left);
      expect(erg.width, hero.width); // ERG card is as wide as the tiles
      expect(summary.right, bar.right); // right column ends at the bar's edge
      expect(summary.left, greaterThan(hero.right));
      // The tiles' small row spans the hero tile exactly.
      final lastSmall = tester.getRect(find.byType(MetricTile).at(3));
      expect(lastSmall.right, closeTo(hero.right, 0.5));

      c.read(recorderProvider.notifier).discard();
      await tester.pump();
    });

    testWidgets('the chart uses the available height', (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await tester.tap(find.text('Record'));
      await tester.pump();

      final chart = tester.getSize(find.byType(RideChart));
      expect(chart.height, greaterThan(300)); // narrow layout is 240
      expect(chart.width, greaterThan(500));

      c.read(recorderProvider.notifier).discard();
      await tester.pump();
    });

    testWidgets('before recording the right side invites you to record',
        (tester) async {
      await openDashboard(tester, size: desktop);

      expect(find.text('Press Record to start this ride'), findsOneWidget);
      expect(find.byType(WorkoutSummary), findsNothing);
      expect(find.byType(RideChart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hint goes away once recording', (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await tester.tap(find.text('Record'));
      await tester.pump();

      expect(find.text('Press Record to start this ride'), findsNothing);

      c.read(recorderProvider.notifier).discard();
      await tester.pump();
    });

    testWidgets('a narrow window stacks instead, with no hint', (tester) async {
      await openDashboard(tester, size: const Size(700, 2000));

      expect(find.text('Press Record to start this ride'), findsNothing);
      final tile = tester.getRect(find.byType(MetricTile).first);
      expect(tester.getTopLeft(find.text('100 W')).dy, greaterThan(tile.bottom));
    });
  });
}
