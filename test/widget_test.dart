import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/main.dart';
import 'package:indoor_cycling/ui/trainer_controller.dart';

void main() {
  testWidgets('connects to the simulated trainer and shows live data',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const IndoorCyclingApp()));
    expect(find.text('Connect your trainer'), findsOneWidget);
    // The simulated trainer is a developer feature, in Preferences.
    expect(find.textContaining('simulated'), findsNothing);

    container.read(trainerControllerProvider.notifier).connectSimulated();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ERG'), findsOneWidget); // the ERG | Road switch

    await tester.tap(find.byTooltip('View and trainer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Connect your trainer'), findsOneWidget);
  });
}
