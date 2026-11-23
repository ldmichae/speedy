import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/dashboard_layout.dart';
import 'package:indoor_cycling/devices/ble/ble_transport.dart';
import 'package:indoor_cycling/ui/dashboard_tiles.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';
import 'package:indoor_cycling/ui/world_view.dart'
    show worldGearExpandedProvider;

import 'fakes/in_memory_ble_transport.dart';

void main() {
  Finder bar(int gear) =>
      find.byWidgetPredicate((w) => w is GearBar && w.gear == gear);

  testWidgets('the ERG tile shows the gear on its bar while simulating',
      (tester) async {
    final container = ProviderContainer(overrides: [
      bleTransportProvider.overrideWithValue(InMemoryBleTransport())
    ]);
    addTearDown(container.dispose);
    final trainer = container.read(trainerControllerProvider.notifier);
    await tester.runAsync(() async {
      await trainer.connectTo(const BleScanResult(id: 'k', name: 'KICKR'));
      await trainer.setGrade(3);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  height: 140,
                  child: DashboardTile(kind: TileKind.ergTarget)))),
    ));
    expect(bar(12), findsOneWidget);

    await tester.runAsync(() => trainer.shift(2));
    await tester.pump();
    expect(find.text('Gear 14'), findsOneWidget);
    expect(bar(14), findsOneWidget);

    await tester.runAsync(trainer.disconnect);
  });

  testWidgets('a bar too narrow for its notches draws nothing, not a crash',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(child: SizedBox(width: 10, child: GearBar(gear: 5)))));
    expect(tester.takeException(), isNull);
  });

  test('the World gear readout starts full size and toggles to a chip', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(worldGearExpandedProvider), isTrue);
    c.read(worldGearExpandedProvider.notifier).toggle();
    expect(c.read(worldGearExpandedProvider), isFalse);
    c.read(worldGearExpandedProvider.notifier).toggle();
    expect(c.read(worldGearExpandedProvider), isTrue);
  });
}
