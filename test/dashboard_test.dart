import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/dashboard_layout.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/rider_profile.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/ui/dashboard_layout_controller.dart';
import 'package:indoor_cycling/ui/dashboard_tiles.dart';
import 'package:indoor_cycling/ui/dashboard_view.dart';
import 'package:indoor_cycling/ui/focus_views.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/recording_panel.dart';
import 'package:indoor_cycling/ui/ride_view_controller.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';
import 'package:indoor_cycling/ui/rider_profile_controller.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/in_memory_ble_transport.dart';

const stacked = Size(900, 2400); // below the 1000px breakpoint: sides stack
const desktop = Size(1400, 1800); // sides sit side by side

/// A dashboard on a connected simulated trainer. The trainer runs on real
/// timers, so it is brought up outside the test's fake clock.
Future<ProviderContainer> openDashboard(WidgetTester tester,
    {Size size = stacked, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    bleTransportProvider.overrideWithValue(InMemoryBleTransport()),
  ]);
  addTearDown(container.dispose);
  final trainer = container.read(trainerControllerProvider.notifier);
  container.read(dashboardLayoutProvider); // start loading the saved layout

  await tester.runAsync(() async {
    await trainer.connectSimulated();
    for (var i = 0; i < 100; i++) {
      final s = container.read(trainerControllerProvider);
      if (s.status == TrainerStatus.connected && s.latest != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  addTearDown(() => tester.runAsync(trainer.disconnect));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: DashboardView())),
  ));
  return container;
}

Finder tile(TileKind k) => find.byKey(ValueKey('tile-${k.name}'));
Rect rect(WidgetTester t, TileKind k) => t.getRect(tile(k));
DashboardLayout layoutOf(ProviderContainer c) => c.read(dashboardLayoutProvider);
List<TileKind> leftOf(ProviderContainer c) => [for (final t in layoutOf(c).left) t.kind];
List<TileKind> rightOf(ProviderContainer c) => [for (final t in layoutOf(c).right) t.kind];
int targetOf(ProviderContainer c) => c.read(trainerControllerProvider).targetWatts;
RecStatus recStatus(ProviderContainer c) => c.read(recorderProvider).status;

const hint = 'Your ride shows up here';

Future<void> record(WidgetTester tester) async {
  await tester.tap(find.text('Record'));
  await tester.pump();
}

Future<void> stopRecording(WidgetTester tester, ProviderContainer c) async {
  c.read(recorderProvider.notifier).discard(); // also stops the 1 s timer
  await tester.pump();
}

/// Opens the ⋮ menu on the record bar and taps one of its items.
Future<void> menuTap(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('View and trainer'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Future<void> startEditing(WidgetTester tester) async {
  await menuTap(tester, 'Edit layout');
  await tester.pumpAndSettle();
}

Future<void> openSettings(WidgetTester tester, TileKind k) async {
  await tester.tap(find.byKey(Key('tile-settings-${k.name}')));
  await tester.pumpAndSettle();
}

/// Nothing on screen overlaps anything else.
void expectNoTileOverlap(WidgetTester tester, Iterable<TileKind> kinds) {
  final rects = {for (final k in kinds) k: rect(tester, k)};
  for (final a in rects.entries) {
    for (final b in rects.entries) {
      if (a.key.index < b.key.index) {
        expect(a.value.overlaps(b.value), isFalse,
            reason: '${a.key.name} overlaps ${b.key.name}');
      }
    }
  }
}

/// The simulated trainer's streams live in the real-time zone, so a
/// disconnect only finishes once real time passes.
Future<void> settleDisconnect(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pumpAndSettle();
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  group('tiles and recording', () {
    testWidgets('before recording: live tiles and the ERG controls, no totals or chart',
        (tester) async {
      await openDashboard(tester);

      expect(find.text('Record'), findsOneWidget);
      for (final k in [
        TileKind.powerAvg,
        TileKind.ergTarget,
        TileKind.cadence,
        TileKind.speed,
        TileKind.heartRate,
        TileKind.time,
      ]) {
        expect(tile(k), findsOneWidget, reason: k.name);
      }
      for (final k in [
        TileKind.distance,
        TileKind.avgPower,
        TileKind.energy,
        TileKind.chart,
      ]) {
        expect(tile(k), findsNothing, reason: k.name);
      }
      expect(find.byType(RideChart), findsNothing);
    });

    testWidgets('recording reveals distance, average power, energy and the chart',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      expect(recStatus(c), RecStatus.recording);
      for (final k in [
        TileKind.distance,
        TileKind.avgPower,
        TileKind.energy,
        TileKind.chart,
      ]) {
        expect(tile(k), findsOneWidget, reason: k.name);
      }
      expect(tile(TileKind.time), findsOneWidget);
      expect(find.byType(RideChart), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);

      await stopRecording(tester, c);
    });

    testWidgets('discarding hides the totals and chart again', (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('End ride?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(recStatus(c), RecStatus.idle);
      expect(tile(TileKind.chart), findsNothing);
      expect(tile(TileKind.distance), findsNothing);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('pausing keeps the totals and chart on screen', (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      await tester.tap(find.text('Pause'));
      await tester.pump();

      expect(recStatus(c), RecStatus.paused);
      expect(tile(TileKind.chart), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await stopRecording(tester, c);
    });

    testWidgets('the Record bar stays put when recording starts', (tester) async {
      final c = await openDashboard(tester);
      final before = tester.getTopLeft(find.byType(WorkoutBar)).dy;

      await record(tester);

      // Only the outline's padding and border appear around it.
      expect((tester.getTopLeft(find.byType(WorkoutBar)).dy - before).abs(),
          lessThan(16));
      await stopRecording(tester, c);
    });

    testWidgets('the bar\'s buttons are at least 48 px tall', (tester) async {
      final c = await openDashboard(tester);
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Record')).height,
          greaterThanOrEqualTo(48));

      await record(tester);
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Pause')).height,
          greaterThanOrEqualTo(48));
      expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Stop')).height,
          greaterThanOrEqualTo(48));
      await stopRecording(tester, c);
    });
  });

  group('power tile and ERG controls', () {
    testWidgets('the power tile carries the target and how far off it is',
        (tester) async {
      await openDashboard(tester);

      expect(find.text('Target 100 W'), findsOneWidget);
      // The simulated trainer is still warming up, well under 100 W.
      expect(find.descendant(of: tile(TileKind.powerAvg), matching: find.byType(TargetChip)),
          findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('the target on the power tile follows the ERG buttons',
        (tester) async {
      await openDashboard(tester);

      await tester.tap(find.byTooltip('Raise target by 5 W'));
      await tester.pump();

      expect(find.text('Target 105 W'), findsOneWidget);
      expect(find.text('Target 100 W'), findsNothing);
    });

    testWidgets('the ERG tile is one slim stepper; tapping the step size cycles it',
        (tester) async {
      final c = await openDashboard(tester);

      expect(tester.getSize(tile(TileKind.ergTarget)).height, lessThan(110));
      expect(find.descendant(of: tile(TileKind.ergTarget), matching: find.text('100 W')),
          findsOneWidget);

      await tester.tap(find.text('±5 W'));
      await tester.pump();
      await tester.tap(find.byTooltip('Lower target by 10 W'));
      await tester.pump();
      expect(targetOf(c), 90);
      expect(find.descendant(of: tile(TileKind.ergTarget), matching: find.text('90 W')),
          findsOneWidget);

      await tester.tap(find.text('±10 W'));
      await tester.pump();
      expect(find.text('±25 W'), findsOneWidget);
      await tester.tap(find.byTooltip('Raise target by 25 W'));
      await tester.pump();
      expect(targetOf(c), 115);
    });

    testWidgets('on phone width the controls are on the first screen under power',
        (tester) async {
      await openDashboard(tester, size: const Size(480, 1000));

      final power = rect(tester, TileKind.powerAvg);
      final erg = rect(tester, TileKind.ergTarget);
      expect(erg.top, closeTo(power.bottom + 12, 0.5)); // directly beneath
      expect(erg.bottom, lessThan(1000)); // no scrolling to change the target
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ERG buttons still change the target', (tester) async {
      final c = await openDashboard(tester);
      await tester.tap(find.byTooltip('Raise target by 5 W'));
      await tester.pump();
      expect(targetOf(c), 105);
    });
  });

  group('blank tiles say why', () {
    testWidgets('heart rate without a sensor says so', (tester) async {
      await openDashboard(tester);
      expect(find.descendant(of: tile(TileKind.heartRate), matching: find.text('No sensor')),
          findsOneWidget);
    });

    testWidgets('energy without a rider profile says what is missing',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      expect(find.descendant(of: tile(TileKind.energy), matching: find.text('Add profile')),
          findsOneWidget);
      await stopRecording(tester, c);
    });

    testWidgets('with a complete profile the note goes away', (tester) async {
      final c = await openDashboard(tester);
      c.read(riderProfileProvider.notifier).update(const RiderProfile(
          heightCm: 180, weightKg: 75, age: 30, sex: Sex.male));
      await record(tester);

      expect(find.text('Add profile'), findsNothing);
      await stopRecording(tester, c);
    });

    testWidgets('an empty right side explains what will appear there',
        (tester) async {
      await openDashboard(tester, size: desktop);
      expect(find.text(hint), findsOneWidget);
      expect(find.textContaining('once you press Record'), findsOneWidget);
    });

    testWidgets('the explanation is gone once recording, and while editing',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);
      expect(find.text(hint), findsNothing);
      await stopRecording(tester, c);

      await startEditing(tester);
      expect(find.text(hint), findsNothing);
      expect(tile(TileKind.chart), findsOneWidget); // the real tiles instead
    });

  });

  group('keyboard', () {
    testWidgets('Space starts, pauses and resumes the recording', (tester) async {
      final c = await openDashboard(tester);
      expect(recStatus(c), RecStatus.idle);

      await key(tester, LogicalKeyboardKey.space);
      expect(recStatus(c), RecStatus.recording);
      await key(tester, LogicalKeyboardKey.space);
      expect(recStatus(c), RecStatus.paused);
      await key(tester, LogicalKeyboardKey.space);
      expect(recStatus(c), RecStatus.recording);

      await stopRecording(tester, c);
    });

    testWidgets('arrow keys move the target by 5 W, Shift by 25 W', (tester) async {
      final c = await openDashboard(tester);

      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(targetOf(c), 105);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(targetOf(c), 95);
      await key(tester, LogicalKeyboardKey.arrowUp, shift: true);
      expect(targetOf(c), 120);
      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(targetOf(c), 95);
    });

    testWidgets('keys do nothing while arranging tiles', (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.space);

      expect(targetOf(c), 100);
      expect(recStatus(c), RecStatus.idle);
    });

    testWidgets('after clicking a button, Space is not that button\'s press again',
        (tester) async {
      final c = await openDashboard(tester);

      await tester.tap(find.byTooltip('Raise target by 5 W'));
      await tester.pumpAndSettle();
      expect(targetOf(c), 105);

      await key(tester, LogicalKeyboardKey.space);

      expect(recStatus(c), RecStatus.recording); // Space did the bar's job
      expect(targetOf(c), 105); // and did not press +5 a second time
      await stopRecording(tester, c);
    });

    testWidgets('arrow keys do not reach the dashboard through an open dialog',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('End ride?'), findsOneWidget);

      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(targetOf(c), 100);

      await tester.tap(find.text('Keep riding'));
      await tester.pumpAndSettle();
      await stopRecording(tester, c);
    });

  });

  group('Disconnect', () {
    testWidgets('disconnects straight away when not recording', (tester) async {
      final c = await openDashboard(tester);

      await menuTap(tester, 'Disconnect');
      await settleDisconnect(tester);

      expect(find.text('Disconnect the trainer?'), findsNothing);
      expect(c.read(trainerControllerProvider).status, TrainerStatus.disconnected);
    });

    testWidgets('asks first mid-ride; Keep riding leaves everything running',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      await menuTap(tester, 'Disconnect');
      await tester.pumpAndSettle();
      expect(find.text('Disconnect the trainer?'), findsOneWidget);
      expect(find.textContaining('recording pauses'), findsOneWidget);

      await tester.tap(find.text('Keep riding'));
      await tester.pumpAndSettle();

      expect(c.read(trainerControllerProvider).status, TrainerStatus.connected);
      expect(recStatus(c), RecStatus.recording);
      await stopRecording(tester, c);
    });

    testWidgets('confirming mid-ride disconnects and pauses the recording',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      await menuTap(tester, 'Disconnect');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await settleDisconnect(tester);

      expect(c.read(trainerControllerProvider).status, TrainerStatus.disconnected);
      expect(recStatus(c), RecStatus.paused); // kept, not lost
      expect(c.read(recorderProvider).samples, isNotEmpty);
      await stopRecording(tester, c);
    });
  });

  group('chart controls', () {
    Finder inOptions(Finder f) =>
        find.descendant(of: find.byType(ChartOptions), matching: f);

    testWidgets('are one compact block, not two rows of chunky chips',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);

      final size = tester.getSize(find.byType(ChartOptions));
      expect(size.height, lessThanOrEqualTo(80));
      expect(tester.getSize(tile(TileKind.chart)).height, greaterThan(size.height * 4));
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      await stopRecording(tester, c);
    });

    testWidgets('tapping a series in the legend shows or hides it', (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);
      expect(c.read(chartSettingsProvider).visible, contains(RideMetric.cadence));

      await tester.tap(inOptions(find.text('Cadence')));
      await tester.pump();
      expect(c.read(chartSettingsProvider).visible, isNot(contains(RideMetric.cadence)));

      await tester.tap(inOptions(find.text('Cadence')));
      await tester.pump();
      expect(c.read(chartSettingsProvider).visible, contains(RideMetric.cadence));
      await stopRecording(tester, c);
    });

    testWidgets('the time window is a menu, defaulting to the whole ride',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);
      expect(inOptions(find.text('Whole ride')), findsOneWidget);
      expect(find.text('Last 5 min'), findsNothing); // tucked away until opened

      await tester.tap(inOptions(find.text('Whole ride')));
      await tester.pumpAndSettle();
      expect(find.text('Last 5 min'), findsOneWidget);
      expect(find.text('Last 10 min'), findsOneWidget);
      expect(find.text('Last 20 min'), findsOneWidget);

      await tester.tap(find.text('Last 5 min'));
      await tester.pumpAndSettle();

      expect(c.read(chartSettingsProvider).window, const Duration(minutes: 5));
      expect(inOptions(find.text('Last 5 min')), findsOneWidget);

      await tester.tap(inOptions(find.text('Last 5 min')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whole ride').last);
      await tester.pumpAndSettle();
      expect(c.read(chartSettingsProvider).window, isNull);
      await stopRecording(tester, c);
    });
  });

  group('stacked layout (narrow window)', () {
    testWidgets('reads top to bottom: bar, power, ERG, small tiles, chart, totals',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      double top(Finder f) => tester.getTopLeft(f).dy;
      final tops = [
        top(find.byType(WorkoutBar)),
        top(tile(TileKind.powerAvg)),
        top(tile(TileKind.ergTarget)),
        top(tile(TileKind.speed)),
        top(tile(TileKind.chart)), // the right side starts below the left
        top(tile(TileKind.distance)),
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: 'item $i');
      }
      expect(tester.takeException(), isNull);
      await stopRecording(tester, c);
    });

    testWidgets('full-width tiles share the bar\'s edges; small ones span it',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      final bar = tester.getRect(find.byType(WorkoutBar));
      for (final k in [TileKind.powerAvg, TileKind.chart]) {
        final r = rect(tester, k);
        expect(r.left, closeTo(bar.left, 0.5), reason: k.name);
        expect(r.width, closeTo(bar.width, 0.5), reason: k.name);
      }
      for (final row in [
        [TileKind.speed, TileKind.heartRate, TileKind.time],
        [TileKind.distance, TileKind.avgPower, TileKind.energy],
      ]) {
        final r = [for (final k in row) rect(tester, k)];
        expect(r.first.left, closeTo(bar.left, 0.5));
        expect(r.last.right, closeTo(bar.right, 0.5));
        expect(r[0].width, closeTo(r[1].width, 0.5));
        expect(r[1].width, closeTo(r[2].width, 0.5));
        expect(r[1].left - r[0].right, closeTo(12, 0.5)); // the gap
      }
      await stopRecording(tester, c);
    });
  });

  group('wide layout (desktop): two sides', () {
    testWidgets('power over the ERG controls on the left, chart over totals on the right',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);

      final bar = tester.getRect(find.byType(WorkoutBar));
      final power = rect(tester, TileKind.powerAvg);
      final erg = rect(tester, TileKind.ergTarget);
      final chart = rect(tester, TileKind.chart);
      final distance = rect(tester, TileKind.distance);
      final cadence = rect(tester, TileKind.time);

      expect(power.left, closeTo(bar.left, 0.5));
      expect(chart.right, closeTo(bar.right, 0.5));
      expect(power.width, closeTo(chart.width, 0.5)); // equal halves
      expect(chart.left - power.right, closeTo(16, 0.5)); // the gutter
      expect(chart.top, closeTo(power.top, 0.5)); // both sides start at the top
      expect(erg.left, closeTo(power.left, 0.5));
      expect(erg.top, closeTo(power.bottom + 12, 0.5)); // ERG directly under power
      expect(distance.top, closeTo(chart.bottom + 12, 0.5));
      // The sides end together, so neither leaves a hole.
      expect(cadence.bottom, closeTo(distance.bottom, 0.5));
      expect(tester.takeException(), isNull);
      await stopRecording(tester, c);
    });

    testWidgets('each side has its own three columns', (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);

      final small = [
        for (final k in [TileKind.speed, TileKind.heartRate, TileKind.time])
          rect(tester, k)
      ];
      final side = rect(tester, TileKind.powerAvg);
      expect(small.first.left, closeTo(side.left, 0.5));
      expect(small.last.right, closeTo(side.right, 0.5));
      // Three tiles across the side, not the window.
      expect(small[0].width, closeTo((side.width - 24) / 3, 0.5));
      await stopRecording(tester, c);
    });

    testWidgets('before recording the right half holds the explanation, level with power',
        (tester) async {
      await openDashboard(tester, size: desktop);

      final power = rect(tester, TileKind.powerAvg);
      final hintRect = tester.getRect(find.ancestor(
          of: find.text(hint), matching: find.byType(Card)).first);
      expect(hintRect.left, greaterThan(power.right));
      expect(hintRect.top, closeTo(power.top, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a side with nothing visible leaves the other at half width',
        (tester) async {
      // Everything on the right is ride-only, so before recording it is empty.
      final layout = DashboardLayout(
        left: DashboardLayout.standard.left,
        right: const [TileConfig(TileKind.chart, 3, 4)],
      );
      final c = await openDashboard(tester,
          size: desktop, prefs: {'dashboardLayout': layout.toJson()});
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(WorkoutBar));
      final power = rect(tester, TileKind.powerAvg);
      expect(power.width, lessThan(bar.width / 2)); // not stretched to fill
      expect(layoutOf(c).right, hasLength(1));
    });
  });

  group('editing the layout', () {
    testWidgets('Edit layout shows every tile and a toolbar; Done leaves',
        (tester) async {
      await openDashboard(tester);
      expect(tile(TileKind.chart), findsNothing);

      await startEditing(tester);

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Add tile'), findsOneWidget);
      expect(find.text('Reset to default'), findsOneWidget);
      expect(tile(TileKind.chart), findsOneWidget); // ride tiles can be arranged
      expect(tile(TileKind.distance), findsOneWidget);
      expect(find.text('Edit layout'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('View and trainer'));
      await tester.pumpAndSettle();
      expect(find.text('Edit layout'), findsOneWidget);
      expect(tile(TileKind.chart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tile contents are inert while editing', (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await tester.tap(find.byTooltip('Raise target by 5 W'), warnIfMissed: false);
      await tester.pump();

      expect(targetOf(c), 100);
    });

    testWidgets('resize a tile from its settings', (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);
      final before = rect(tester, TileKind.cadence);

      await openSettings(tester, TileKind.cadence);
      await tester.tap(find.widgetWithText(ChoiceChip, '2/3'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '2 rows'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();

      final cfg = layoutOf(c).all.firstWhere((t) => t.kind == TileKind.cadence);
      expect((cfg.span, cfg.rows), (2, 2));
      final after = rect(tester, TileKind.cadence);
      expect(after.height, greaterThan(before.height * 1.9));
      expect(after.width, greaterThan(before.width * 1.9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tile cannot be made smaller than its content needs',
        (tester) async {
      await openDashboard(tester);
      await startEditing(tester);

      await openSettings(tester, TileKind.ergTarget);

      ChoiceChip chip(String label) =>
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(chip('1 row').onSelected, isNotNull); // one row is enough
      expect(chip('2 rows').onSelected, isNotNull);
      expect(chip('1/3').onSelected, isNull); // needs at least 2/3
      expect(chip('2/3').onSelected, isNotNull);
      expect(chip('Full').onSelected, isNotNull);
    });

    testWidgets('choose which metric a tile shows; a placed one swaps',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);
      expect(leftOf(c).sublist(2, 5),
          [TileKind.cadence, TileKind.speed, TileKind.heartRate]);

      await openSettings(tester, TileKind.cadence);
      await tester.tap(find.byType(DropdownButton<TileKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speed').last);
      await tester.pumpAndSettle();

      expect(leftOf(c).sublist(2, 5),
          [TileKind.speed, TileKind.cadence, TileKind.heartRate]);
      expect(layoutOf(c).all.map((t) => t.kind).toSet(),
          hasLength(layoutOf(c).all.length)); // no repeats
      // The open dialog follows the tile, whose title is now Speed.
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect((dialog.title! as Text).data, 'Speed');
    });

    testWidgets('a tile can swap places with one on the other side',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await openSettings(tester, TileKind.cadence);
      await tester.tap(find.byType(DropdownButton<TileKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chart').last);
      await tester.pumpAndSettle();

      expect(layoutOf(c).sideOf(TileKind.chart), Side.left);
      expect(layoutOf(c).sideOf(TileKind.cadence), Side.right);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing a metric that is not on the dashboard replaces it',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await openSettings(tester, TileKind.heartRate);
      await tester.tap(find.byType(DropdownButton<TileKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Power').last); // plain power, not placed
      await tester.pumpAndSettle();

      expect(leftOf(c), contains(TileKind.powerNow));
      expect(leftOf(c), isNot(contains(TileKind.heartRate)));
    });

    testWidgets('remove a tile, then add it back', (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await openSettings(tester, TileKind.cadence);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(tile(TileKind.cadence), findsNothing);
      expect(layoutOf(c).sideOf(TileKind.cadence), isNull);

      await tester.tap(find.text('Add tile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cadence').last);
      await tester.pumpAndSettle();

      expect(tile(TileKind.cadence), findsOneWidget);
      // Both sides are 5 rows tall, so it goes to the left.
      expect(layoutOf(c).sideOf(TileKind.cadence), Side.left);
      expect(leftOf(c).last, TileKind.cadence);
    });

    testWidgets('the Time tile is available to add, since it is not on by default',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await tester.tap(find.text('Add tile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time').last);
      await tester.pumpAndSettle();

      expect(layoutOf(c).sideOf(TileKind.time), isNotNull);
      expect(tile(TileKind.time), findsOneWidget);
    });

    testWidgets('Add tile is disabled when everything is already placed',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);
      c.read(dashboardLayoutProvider.notifier)
        ..add(TileKind.powerNow)
        ..add(TileKind.time)
        ..add(TileKind.route);
      await tester.pump();

      final menu = tester.widget<PopupMenuButton<TileKind>>(
          find.byType(PopupMenuButton<TileKind>));
      expect(menu.enabled, isFalse);
    });

    testWidgets('both sides are marked out while editing', (tester) async {
      await openDashboard(tester, size: desktop);
      await startEditing(tester);

      expect(tester.takeException(), isNull);
      // Left and right grids are separate drop zones, side by side.
      expect(find.byType(DragTarget<TileKind>), findsNWidgets(2));
    });

    group('dragging', () {
      /// Starts dragging [kind] by its centre; returns the gesture and the
      /// offset from the tile's top-left corner to where it was grabbed.
      Future<(TestGesture, Offset)> grab(WidgetTester tester, TileKind kind) async {
        final r = rect(tester, kind);
        final g = await tester.startGesture(r.center);
        await g.moveBy(const Offset(-30, 0)); // past the drag slop
        await tester.pump();
        return (g, r.center - r.topLeft);
      }

      /// Moves a grabbed tile so its top-left corner is at [corner].
      Future<void> dragCorner(WidgetTester tester, TestGesture g, Offset grabbed,
          Offset corner) async {
        await g.moveTo(corner + grabbed);
        await tester.pump(); // the frame the slide starts in
        await tester.pump(const Duration(milliseconds: 300)); // let tiles slide
      }

      testWidgets('on a side, the others shove aside to the next open slots',
          (tester) async {
        final c = await openDashboard(tester);
        await startEditing(tester);
        final cad = rect(tester, TileKind.cadence);
        final speed = rect(tester, TileKind.speed);
        final hr = rect(tester, TileKind.heartRate);

        final (g, grabbed) = await grab(tester, TileKind.heartRate);
        await dragCorner(tester, g, grabbed, cad.topLeft); // onto cadence's slot

        // Nothing is saved yet, but the grid already shows the result:
        expect(leftOf(c).sublist(2, 5),
            [TileKind.cadence, TileKind.speed, TileKind.heartRate]);
        expect(rect(tester, TileKind.heartRate).topLeft, cad.topLeft);
        expect(rect(tester, TileKind.cadence).left, closeTo(speed.left, 0.5));
        expect(rect(tester, TileKind.speed).left, closeTo(hr.left, 0.5));

        await g.up();
        await tester.pumpAndSettle();

        // Dropping commits exactly what was previewed.
        expect(leftOf(c).sublist(2, 5),
            [TileKind.heartRate, TileKind.cadence, TileKind.speed]);
        expect(rect(tester, TileKind.heartRate).topLeft, cad.topLeft);
        expect(rect(tester, TileKind.cadence).left, closeTo(speed.left, 0.5));
        expect(rect(tester, TileKind.speed).left, closeTo(hr.left, 0.5));
      });

      testWidgets('dragging off the grid and letting go puts everything back',
          (tester) async {
        final c = await openDashboard(tester);
        await startEditing(tester);
        final before = layoutOf(c).toJson();
        final all = layoutOf(c).all.map((t) => t.kind).toList();
        final originals = {for (final k in all) k: rect(tester, k)};

        final (g, grabbed) = await grab(tester, TileKind.heartRate);
        await dragCorner(tester, g, grabbed, rect(tester, TileKind.cadence).topLeft);
        expect(rect(tester, TileKind.cadence), isNot(originals[TileKind.cadence]));

        await g.moveTo(const Offset(4, 4)); // outside both sides
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // The preview is withdrawn straight away.
        expect(rect(tester, TileKind.cadence), originals[TileKind.cadence]);

        await g.up();
        await tester.pumpAndSettle();

        expect(layoutOf(c).toJson(), before);
        for (final k in all) {
          expect(rect(tester, k), originals[k], reason: k.name);
        }
      });

      testWidgets('dropping beneath a side lands in its last row, at the drop column',
          (tester) async {
        final c = await openDashboard(tester);
        await startEditing(tester);
        final power = rect(tester, TileKind.powerAvg);
        final lastRow = rect(tester, TileKind.speed); // the last row of small tiles

        final (g, grabbed) = await grab(tester, TileKind.heartRate);
        await dragCorner(tester, g, grabbed, Offset(power.left, lastRow.bottom + 24));
        await g.up();
        await tester.pumpAndSettle();

        // Heart rate takes the first slot of the last row; the others move on.
        expect(leftOf(c).sublist(2, 5),
            [TileKind.cadence, TileKind.heartRate, TileKind.speed]);
        expect(rect(tester, TileKind.heartRate).left, closeTo(power.left, 0.5));
        expect(rect(tester, TileKind.heartRate).top, closeTo(lastRow.top, 0.5));
      });

      testWidgets('a tile can be dragged to the other side', (tester) async {
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);
        final cad = rect(tester, TileKind.cadence);
        final avgPower = rect(tester, TileKind.avgPower);

        final (g, grabbed) = await grab(tester, TileKind.avgPower);
        await dragCorner(tester, g, grabbed, cad.topLeft); // onto the left side

        // The preview already shows it moved: the right side closes up.
        expect(rect(tester, TileKind.energy).left, closeTo(avgPower.left, 0.5));
        expect(layoutOf(c).sideOf(TileKind.avgPower), Side.right); // not saved yet

        await g.up();
        await tester.pumpAndSettle();

        expect(layoutOf(c).sideOf(TileKind.avgPower), Side.left);
        expect(leftOf(c).indexOf(TileKind.avgPower), 2); // just under the ERG controls
        expect(rightOf(c), [TileKind.chart, TileKind.distance, TileKind.energy]);
        expect(rect(tester, TileKind.avgPower).topLeft, cad.topLeft);
        expectNoTileOverlap(tester, layoutOf(c).all.map((t) => t.kind));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a dragged-across tile is fully usable afterwards',
          (tester) async {
        // Its original widget was removed mid-drag; nothing may be left stuck.
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);

        final (g, grabbed) = await grab(tester, TileKind.avgPower);
        await dragCorner(
            tester, g, grabbed, rect(tester, TileKind.cadence).topLeft);
        await g.up();
        await tester.pumpAndSettle();

        await openSettings(tester, TileKind.avgPower); // gear still works
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();

        // And it can be dragged again, back to the right.
        final (g2, grabbed2) = await grab(tester, TileKind.avgPower);
        await dragCorner(
            tester, g2, grabbed2, rect(tester, TileKind.chart).topLeft);
        await g2.up();
        await tester.pumpAndSettle();
        expect(layoutOf(c).sideOf(TileKind.avgPower), Side.right);
      });

      testWidgets('dropping below a full last row on the other side starts a new row',
          (tester) async {
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);
        final chart = rect(tester, TileKind.chart);
        final lastRow = rect(tester, TileKind.energy); // distance / avg / energy

        final (g, grabbed) = await grab(tester, TileKind.cadence);
        await dragCorner(tester, g, grabbed, Offset(chart.left, lastRow.bottom + 24));
        await g.up();
        await tester.pumpAndSettle();

        expect(layoutOf(c).sideOf(TileKind.cadence), Side.right);
        expect(rightOf(c).last, TileKind.cadence);
        expect(rect(tester, TileKind.cadence).top, greaterThan(lastRow.bottom - 1));
        expect(leftOf(c), isNot(contains(TileKind.cadence)));
      });

      testWidgets('a big tile dropped on small ones pushes them clear',
          (tester) async {
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);
        final power = rect(tester, TileKind.powerAvg);

        final (g, grabbed) = await grab(tester, TileKind.chart);
        await dragCorner(tester, g, grabbed, power.topLeft);
        await g.up();
        await tester.pumpAndSettle();

        expect(leftOf(c).first, TileKind.chart);
        expect(rect(tester, TileKind.chart).topLeft, power.topLeft); // took the slot
        final kinds = layoutOf(c).all.map((t) => t.kind).toList();
        expect(kinds, hasLength(DashboardLayout.standard.all.length)); // none lost
        expectNoTileOverlap(tester, kinds);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an emptied side still takes a drop', (tester) async {
        final c = await openDashboard(tester, size: desktop);
        for (final t in [...layoutOf(c).right]) {
          c.read(dashboardLayoutProvider.notifier)
              .moveTo(t.kind, Side.left, 99);
        }
        await tester.pump();
        await startEditing(tester);
        expect(rightOf(c), isEmpty);
        expect(find.text('Drop tiles here'), findsOneWidget);

        final zone = tester.getCenter(find.text('Drop tiles here'));
        final r = rect(tester, TileKind.cadence);
        final g = await tester.startGesture(r.center);
        await g.moveBy(const Offset(30, 0));
        await tester.pump();
        await g.moveTo(zone);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await g.up();
        await tester.pumpAndSettle();

        expect(rightOf(c), [TileKind.cadence]);
        expect(find.text('Drop tiles here'), findsNothing);
      });

      testWidgets('dropping a tile on itself changes nothing', (tester) async {
        final c = await openDashboard(tester);
        await startEditing(tester);
        final before = layoutOf(c).toJson();

        final at = tester.getCenter(tile(TileKind.speed));
        final g = await tester.startGesture(at);
        await g.moveBy(const Offset(40, 10));
        await tester.pump();
        await g.moveTo(at);
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();

        expect(layoutOf(c).toJson(), before);
      });
    });

    testWidgets('changes are saved, and Reset restores the default',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);
      TextButton reset() => tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Reset to default'));
      expect(reset().onPressed, isNull); // already the default

      c.read(dashboardLayoutProvider.notifier).remove(TileKind.speed);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));

      expect(tile(TileKind.speed), findsNothing);
      expect(reset().onPressed, isNotNull);
      final saved = (await SharedPreferences.getInstance()).getString('dashboardLayout');
      expect(saved, isNotNull);
      expect(saved, isNot(contains('speed')));

      await tester.tap(find.text('Reset to default'));
      await tester.pumpAndSettle();

      expect(tile(TileKind.speed), findsOneWidget);
      expect(layoutOf(c).toJson(), DashboardLayout.standard.toJson());
    });

    testWidgets('a saved layout is used when the dashboard opens', (tester) async {
      final custom = DashboardLayout.standard
          .moveTo(TileKind.heartRate, Side.left, 0)
          .remove(TileKind.cadence);
      final c = await openDashboard(tester, prefs: {'dashboardLayout': custom.toJson()});
      await tester.pumpAndSettle();

      expect(leftOf(c).first, TileKind.heartRate);
      expect(tile(TileKind.cadence), findsNothing);
      expect(rect(tester, TileKind.heartRate).top,
          lessThan(rect(tester, TileKind.powerAvg).top + 1));
    });
  });

  group('map and chart views', () {
    for (final (name, size) in [
      ('Chart', const Size(1400, 900)),
      ('Map', const Size(1400, 900)),
      ('Chart', const Size(700, 1000)),
    ]) {
      testWidgets('$name view at $size fits without scrolling, no editable grid',
          (tester) async {
        await openDashboard(tester, size: size);
        await tester.tap(find.descendant(
            of: find.byType(SegmentedButton<RideView>), matching: find.text(name)));
        await tester.pumpAndSettle();

        expect(find.byType(MetricStrip), findsOneWidget);
        expect(find.text('Edit layout'), findsNothing);
        expect(tile(TileKind.cadence), findsNothing);
        final scroll =
            tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scroll.position.maxScrollExtent, 0);
      });
    }
  });
}
