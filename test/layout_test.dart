import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_record.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/ui/history_screen.dart';
import 'package:indoor_cycling/ui/preferences_screen.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';
import 'package:indoor_cycling/ui/ride_history_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/in_memory_ride_history_store.dart';

const desktop = Size(1400, 900);
const portrait = Size(700, 1600);

RideRecord ride(DateTime at) => RideRecord(startedAt: at, samples: const [
      RideSample(t: 0, power: 200, speed: 36),
      RideSample(t: 60, power: 200, speed: 36),
    ]);

Future<void> pumpAt(WidgetTester tester, Size size, Widget home,
    {InMemoryRideHistoryStore? store}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (store != null) rideHistoryStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

InMemoryRideHistoryStore twoRides() {
  final store = InMemoryRideHistoryStore();
  for (final r in [
    ride(DateTime(2026, 11, 13, 14, 5)),
    ride(DateTime(2026, 11, 12, 9, 30)),
  ]) {
    store.rides[r.id] = jsonEncode(r.toJson());
  }
  return store;
}

/// The card holding the preferences section titled [title].
Rect section(WidgetTester tester, String title) => tester.getRect(
    find.ancestor(of: find.text(title), matching: find.byType(Card)).first);

void main() {
  group('preferences', () {
    testWidgets('two aligned columns on a desktop window', (tester) async {
      await pumpAt(tester, desktop, const PreferencesScreen());

      final appearance = section(tester, 'Appearance');
      final recording = section(tester, 'Recording');
      final units = section(tester, 'Units');
      final profile = section(tester, 'Rider profile');

      // Cards in a column share one left edge and one width.
      expect(recording.left, appearance.left);
      expect(recording.width, appearance.width);
      expect(profile.left, units.left);
      expect(profile.width, units.width);
      // The two columns are the same width, side by side, tops aligned.
      expect(units.width, closeTo(appearance.width, 1));
      expect(units.left, greaterThan(appearance.right));
      expect(units.top, appearance.top);
      // And stacked in order within each column.
      expect(recording.top, greaterThan(appearance.bottom - 1));
      expect(profile.top, greaterThan(units.bottom - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('one aligned column when narrow', (tester) async {
      await pumpAt(tester, portrait, const PreferencesScreen());

      final cards = [
        for (final t in ['Appearance', 'Recording', 'Units', 'Rider profile'])
          section(tester, t)
      ];
      expect({for (final c in cards) c.left}, hasLength(1));
      expect({for (final c in cards) c.width}, hasLength(1));
      for (var i = 1; i < cards.length; i++) {
        expect(cards[i].top, greaterThan(cards[i - 1].bottom - 1));
      }
    });
  });

  group('history list', () {
    testWidgets('cards sit side by side on a desktop window', (tester) async {
      await pumpAt(tester, desktop, const HistoryScreen(), store: twoRides());

      final a = tester.getTopLeft(find.text('Fri 13 Nov 2026 · 14:05'));
      final b = tester.getTopLeft(find.text('Thu 12 Nov 2026 · 09:30'));
      expect(b.dx, greaterThan(a.dx + 300));
      expect((a.dy - b.dy).abs(), lessThan(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cards stack when narrow, newest first', (tester) async {
      await pumpAt(tester, portrait, const HistoryScreen(), store: twoRides());

      final a = tester.getTopLeft(find.text('Fri 13 Nov 2026 · 14:05'));
      final b = tester.getTopLeft(find.text('Thu 12 Nov 2026 · 09:30'));
      expect(b.dx, a.dx);
      expect(b.dy, greaterThan(a.dy));
    });

    testWidgets('deleting still works in the wide grid', (tester) async {
      final store = twoRides();
      await pumpAt(tester, desktop, const HistoryScreen(), store: store);

      await tester.tap(find.byTooltip('Delete ride').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Fri 13 Nov 2026 · 14:05'), findsNothing);
      expect(find.text('Thu 12 Nov 2026 · 09:30'), findsOneWidget);
    });
  });

  group('ride detail', () {
    final record = ride(DateTime(2026, 11, 13, 14, 5));

    testWidgets('the chart is large on a desktop window', (tester) async {
      await pumpAt(tester, desktop, RideDetailScreen(ride: record));

      final chart = tester.getSize(find.byType(RideChart));
      expect(chart.width, greaterThan(1000));
      expect(chart.height, greaterThan(400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chart keeps its compact size when narrow', (tester) async {
      await pumpAt(tester, portrait, RideDetailScreen(ride: record));

      final chart = tester.getSize(find.byType(RideChart));
      expect(chart.height, 240);
      expect(chart.width, lessThan(720));
    });
  });
}
