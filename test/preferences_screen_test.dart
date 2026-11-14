import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_export.dart';
import 'package:indoor_cycling/ui/preferences_screen.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> openPreferences(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: Center(child: PreferencesButton())),
    ),
  ));
  await tester.tap(find.byType(PreferencesButton));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows palette and recording sections', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openPreferences(tester);

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Teal'), findsOneWidget);
  });

  testWidgets('choosing a save format updates and stores it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await openPreferences(tester);
    expect(container.read(rideFormatProvider), RideFormat.fit);

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();

    expect(container.read(rideFormatProvider), RideFormat.csv);
    expect((await SharedPreferences.getInstance()).getString('rideFormat'),
        'csv');
  });

  testWidgets('a stored format is shown as selected', (tester) async {
    SharedPreferences.setMockInitialValues({'rideFormat': 'csv'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(rideFormatProvider);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PreferencesScreen()),
    ));

    final button = tester.widget<SegmentedButton<RideFormat>>(
        find.byType(SegmentedButton<RideFormat>));
    expect(button.selected, {RideFormat.csv});
  });
}
