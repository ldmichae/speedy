import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/plan.dart';
import 'package:indoor_cycling/ui/dashboard_view.dart';
import 'package:indoor_cycling/ui/history_screen.dart';
import 'package:indoor_cycling/ui/home_screen.dart';
import 'package:indoor_cycling/ui/navigation.dart';
import 'package:indoor_cycling/ui/plan_controller.dart';
import 'package:indoor_cycling/ui/plan_screen.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_history_provider.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:indoor_cycling/devices/trainer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/in_memory_ble_transport.dart';
import 'fakes/in_memory_ride_history_store.dart';

/// A trainer that is simply "connected": no timers, nothing to dispose.
class _ConnectedTrainer extends TrainerController {
  @override
  TrainerState build() =>
      const TrainerState(status: TrainerStatus.connected, deviceName: 'Test trainer');
}

void main() {
  late ProviderContainer container;

  Future<void> open(WidgetTester t, Size size,
      {bool expanded = true, bool connected = false}) async {
    SharedPreferences.setMockInitialValues({'dockExpanded': expanded});
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    container = ProviderContainer(overrides: [
      bleTransportProvider.overrideWithValue(InMemoryBleTransport()),
      if (connected) trainerControllerProvider.overrideWith(_ConnectedTrainer.new),
      rideHistoryStoreProvider.overrideWithValue(InMemoryRideHistoryStore()),
    ]);
    addTearDown(container.dispose);
    container.read(dockExpandedProvider); // load the stored choice
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('wide windows get a dock with labels that collapses to icons',
      (t) async {
    await open(t, const Size(1300, 800));
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(t.widget<NavigationRail>(rail).extended, isTrue);
    expect(find.text('Indoor Cycling'), findsOneWidget);
    for (final p in AppPage.values) {
      expect(find.text(p.label), findsOneWidget);
    }

    await t.tap(find.byTooltip('Collapse menu'));
    await t.pumpAndSettle();
    expect(t.widget<NavigationRail>(rail).extended, isFalse);
    expect(find.text('Indoor Cycling'), findsNothing); // just icons now
    expect(t.getSize(rail).width, lessThanOrEqualTo(80));
    expect(find.byTooltip('Expand menu'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 50));
    expect((await SharedPreferences.getInstance()).getBool('dockExpanded'), isFalse);
  });

  testWidgets('a collapsed choice is remembered', (t) async {
    await open(t, const Size(1300, 800), expanded: false);
    await t.pumpAndSettle();
    expect(t.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
  });

  testWidgets('the dock leads to each page, with no top bar on wide windows',
      (t) async {
    await open(t, const Size(1300, 800));
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Connect your trainer'), findsOneWidget);

    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(container.read(pageProvider), AppPage.history);
    expect(find.byType(HistoryScreen), findsOneWidget);

    await t.tap(find.text('Plans'));
    await t.pumpAndSettle();
    expect(find.byType(PlansScreen), findsOneWidget);
    expect(find.textContaining('No plans yet'), findsOneWidget);
  });

  testWidgets('narrow windows have no rail: a menu bar opens the dock as a drawer',
      (t) async {
    await open(t, const Size(500, 900));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.widgetWithText(AppBar, 'Ride'), findsOneWidget);

    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsOneWidget);

    await t.tap(find.text('Plans'));
    await t.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsNothing); // closed again
    expect(find.widgetWithText(AppBar, 'Plans'), findsOneWidget);
    expect(find.byType(PlansScreen), findsOneWidget);
  });

  testWidgets('leaving the ride page keeps the dashboard alive; starting a plan returns to it',
      (t) async {
    await open(t, const Size(1400, 900), connected: true);
    expect(find.byType(DashboardView), findsOneWidget);

await t.sendKeyEvent(LogicalKeyboardKey.space); // Space records    expect(container.read(recorderProvider).status, RecStatus.recording);
    await t.tap(find.text('History'));
    await t.pump(const Duration(milliseconds: 300));
    // offstage, not rebuilt: its screen wake lock and layout survive
    expect(find.byType(DashboardView, skipOffstage: false), findsOneWidget);
    expect(find.byType(DashboardView), findsNothing);
await t.sendKeyEvent(LogicalKeyboardKey.space); // not while on History    expect(container.read(recorderProvider).status, RecStatus.recording);

    container.read(plansProvider.notifier).save(const Plan('P', [
      PlanBlock([PlanStep(600, 150)])
    ]));
    await t.tap(find.text('Plans'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byTooltip('Start and record'));
    await t.pump();
    expect(container.read(pageProvider), AppPage.ride);
    expect(container.read(planRunProvider), isNotNull);
    expect(find.byType(DashboardView), findsOneWidget);

    container.read(planRunProvider.notifier).stop();
    container.read(recorderProvider.notifier).discard();
  });
}
