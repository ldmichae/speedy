import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/dashboard_layout.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:indoor_cycling/ui/dashboard_layout_controller.dart';
import 'package:indoor_cycling/ui/dashboard_view.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/recording_panel.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';
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

Future<void> record(WidgetTester tester) async {
  await tester.tap(find.text('Record'));
  await tester.pump();
}

Future<void> stopRecording(WidgetTester tester, ProviderContainer c) async {
  c.read(recorderProvider.notifier).discard(); // also stops the 1 s timer
  await tester.pump();
}

Future<void> startEditing(WidgetTester tester) async {
  await tester.tap(find.text('Edit layout'));
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

void main() {
  group('tiles and recording', () {
    testWidgets('before recording: live tiles and ERG target, no totals or chart',
        (tester) async {
      await openDashboard(tester);

      expect(find.text('Ready to ride'), findsOneWidget);
      for (final k in [
        TileKind.powerAvg,
        TileKind.cadence,
        TileKind.speed,
        TileKind.heartRate,
        TileKind.ergTarget,
      ]) {
        expect(tile(k), findsOneWidget, reason: k.name);
      }
      for (final k in [
        TileKind.time,
        TileKind.distance,
        TileKind.avgPower,
        TileKind.energy,
        TileKind.chart,
      ]) {
        expect(tile(k), findsNothing, reason: k.name);
      }
      expect(find.byType(RideChart), findsNothing);
    });

    testWidgets('recording reveals totals incl. distance, and the chart',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      expect(c.read(recorderProvider).status, RecStatus.recording);
      for (final k in [
        TileKind.time,
        TileKind.distance,
        TileKind.avgPower,
        TileKind.energy,
        TileKind.chart,
      ]) {
        expect(tile(k), findsOneWidget, reason: k.name);
      }
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

      expect(c.read(recorderProvider).status, RecStatus.idle);
      expect(tile(TileKind.chart), findsNothing);
      expect(tile(TileKind.distance), findsNothing);
      expect(find.text('Ready to ride'), findsOneWidget);
    });

    testWidgets('pausing keeps the totals and chart on screen', (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      await tester.tap(find.text('Pause'));
      await tester.pump();

      expect(c.read(recorderProvider).status, RecStatus.paused);
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

    testWidgets('the ERG buttons still change the target', (tester) async {
      final c = await openDashboard(tester);
      expect(c.read(trainerControllerProvider).targetWatts, 100);

      await tester.tap(find.text('+25'));
      await tester.pump();

      expect(c.read(trainerControllerProvider).targetWatts, 125);
      expect(find.text('125 W'), findsOneWidget);
    });
  });

  group('stacked layout (narrow window)', () {
    testWidgets('reads top to bottom: bar, left side, then right side',
        (tester) async {
      final c = await openDashboard(tester);
      await record(tester);

      double top(Finder f) => tester.getTopLeft(f).dy;
      final tops = [
        top(find.byType(WorkoutBar)),
        top(tile(TileKind.powerAvg)),
        top(tile(TileKind.cadence)),
        top(tile(TileKind.time)),
        top(tile(TileKind.energy)),
        top(tile(TileKind.ergTarget)), // the right side starts below the left
        top(tile(TileKind.chart)),
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
      for (final k in [
        TileKind.powerAvg,
        TileKind.energy,
        TileKind.ergTarget,
        TileKind.chart,
      ]) {
        final r = rect(tester, k);
        expect(r.left, closeTo(bar.left, 0.5), reason: k.name);
        expect(r.width, closeTo(bar.width, 0.5), reason: k.name);
      }
      for (final row in [
        [TileKind.cadence, TileKind.speed, TileKind.heartRate],
        [TileKind.time, TileKind.distance, TileKind.avgPower],
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
    testWidgets('left and right sides share the width and the top',
        (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);

      final bar = tester.getRect(find.byType(WorkoutBar));
      final power = rect(tester, TileKind.powerAvg);
      final erg = rect(tester, TileKind.ergTarget);
      final chart = rect(tester, TileKind.chart);

      expect(power.left, closeTo(bar.left, 0.5));
      expect(chart.right, closeTo(bar.right, 0.5));
      expect(power.width, closeTo(chart.width, 0.5)); // equal halves
      expect(erg.left, closeTo(chart.left, 0.5)); // one right-hand column
      expect(erg.top, closeTo(power.top, 0.5)); // both sides start at the top
      expect(chart.left - power.right, closeTo(16, 0.5)); // the gutter
      expect(erg.bottom + 12, closeTo(chart.top, 0.5)); // chart under the ERG
      expect(tester.takeException(), isNull);
      await stopRecording(tester, c);
    });

    testWidgets('each side has its own three columns', (tester) async {
      final c = await openDashboard(tester, size: desktop);
      await record(tester);

      final left = [
        for (final k in [TileKind.cadence, TileKind.speed, TileKind.heartRate])
          rect(tester, k)
      ];
      final side = rect(tester, TileKind.powerAvg);
      expect(left.first.left, closeTo(side.left, 0.5));
      expect(left.last.right, closeTo(side.right, 0.5));
      // Three tiles across the side, not the window.
      expect(left[0].width, closeTo((side.width - 24) / 3, 0.5));
      await stopRecording(tester, c);
    });

    testWidgets('before recording, the ERG target is the right side\'s only tile',
        (tester) async {
      await openDashboard(tester, size: desktop);

      final power = rect(tester, TileKind.powerAvg);
      final erg = rect(tester, TileKind.ergTarget);
      expect(erg.left, greaterThan(power.right));
      expect(erg.top, closeTo(power.top, 0.5));
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

      expect(find.text('Edit layout'), findsOneWidget);
      expect(tile(TileKind.chart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tile contents are inert while editing', (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);

      await tester.tap(find.text('+25'), warnIfMissed: false);
      await tester.pump();

      expect(c.read(trainerControllerProvider).targetWatts, 100);
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
      expect(chip('1 row').onSelected, isNull); // disabled
      expect(chip('2 rows').onSelected, isNotNull);
      expect(chip('1/3').onSelected, isNull); // needs at least 2/3
      expect(chip('2/3').onSelected, isNotNull);
      expect(chip('Full').onSelected, isNotNull);
    });

    testWidgets('choose which metric a tile shows; a placed one swaps',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);
      expect(leftOf(c).sublist(1, 4),
          [TileKind.cadence, TileKind.speed, TileKind.heartRate]);

      await openSettings(tester, TileKind.cadence);
      await tester.tap(find.byType(DropdownButton<TileKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speed').last);
      await tester.pumpAndSettle();

      expect(leftOf(c).sublist(1, 4),
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
      await tester.tap(find.text('ERG target').last);
      await tester.pumpAndSettle();

      expect(layoutOf(c).sideOf(TileKind.ergTarget), Side.left);
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
      // Added to the shorter side, which is the left (5 rows against 6).
      expect(layoutOf(c).sideOf(TileKind.cadence), Side.left);
      expect(leftOf(c).last, TileKind.cadence);
    });

    testWidgets('Add tile is disabled when everything is already placed',
        (tester) async {
      final c = await openDashboard(tester);
      await startEditing(tester);
      c.read(dashboardLayoutProvider.notifier).add(TileKind.powerNow);
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
        expect(leftOf(c).sublist(1, 4),
            [TileKind.cadence, TileKind.speed, TileKind.heartRate]);
        expect(rect(tester, TileKind.heartRate).topLeft, cad.topLeft);
        expect(rect(tester, TileKind.cadence).left, closeTo(speed.left, 0.5));
        expect(rect(tester, TileKind.speed).left, closeTo(hr.left, 0.5));

        await g.up();
        await tester.pumpAndSettle();

        // Dropping commits exactly what was previewed.
        expect(leftOf(c).sublist(1, 4),
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

      testWidgets('dropping in the open space below puts the tile last on that side',
          (tester) async {
        final c = await openDashboard(tester);
        await startEditing(tester);
        final last = rect(tester, leftOf(c).last);
        final left = rect(tester, TileKind.powerAvg).left;

        final (g, grabbed) = await grab(tester, TileKind.cadence);
        await dragCorner(tester, g, grabbed, Offset(left, last.bottom + 24));
        await g.up();
        await tester.pumpAndSettle();

        expect(leftOf(c).last, TileKind.cadence);
        expect(rect(tester, TileKind.cadence).top, greaterThan(last.bottom - 1));
      });

      testWidgets('a tile can be dragged to the other side', (tester) async {
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);
        final power = rect(tester, TileKind.powerAvg);
        final chartBefore = rect(tester, TileKind.chart);
        final cad = rect(tester, TileKind.cadence);

        final (g, grabbed) = await grab(tester, TileKind.ergTarget);
        await dragCorner(tester, g, grabbed, cad.topLeft); // onto the left side

        // The preview already shows it moved: the right side closes up.
        expect(rect(tester, TileKind.chart).top, closeTo(power.top, 0.5));
        expect(rect(tester, TileKind.chart).top, lessThan(chartBefore.top));
        expect(rect(tester, TileKind.ergTarget).left, lessThan(power.right));
        expect(layoutOf(c).sideOf(TileKind.ergTarget), Side.right); // not saved yet

        await g.up();
        await tester.pumpAndSettle();

        expect(layoutOf(c).sideOf(TileKind.ergTarget), Side.left);
        expect(leftOf(c).indexOf(TileKind.ergTarget), 1); // straight after power
        expect(rightOf(c), [TileKind.chart]);
        expect(rect(tester, TileKind.ergTarget).left, closeTo(power.left, 0.5));
        expectNoTileOverlap(tester, layoutOf(c).all.map((t) => t.kind));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a dragged-across tile is fully usable afterwards',
          (tester) async {
        // Its original widget was removed mid-drag; nothing may be left stuck.
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);

        final (g, grabbed) = await grab(tester, TileKind.ergTarget);
        await dragCorner(
            tester, g, grabbed, rect(tester, TileKind.cadence).topLeft);
        await g.up();
        await tester.pumpAndSettle();

        await openSettings(tester, TileKind.ergTarget); // gear still works
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();

        // And it can be dragged again.
        final (g2, grabbed2) = await grab(tester, TileKind.ergTarget);
        await dragCorner(
            tester, g2, grabbed2, rect(tester, TileKind.chart).topLeft);
        await g2.up();
        await tester.pumpAndSettle();
        expect(layoutOf(c).sideOf(TileKind.ergTarget), Side.right);
      });

      testWidgets('dropping below the other side\'s tiles puts it last there',
          (tester) async {
        final c = await openDashboard(tester, size: desktop);
        await startEditing(tester);
        final chart = rect(tester, TileKind.chart);

        final (g, grabbed) = await grab(tester, TileKind.cadence);
        await dragCorner(tester, g, grabbed, Offset(chart.left, chart.bottom + 24));
        await g.up();
        await tester.pumpAndSettle();

        expect(layoutOf(c).sideOf(TileKind.cadence), Side.right);
        expect(rightOf(c).last, TileKind.cadence);
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
}
