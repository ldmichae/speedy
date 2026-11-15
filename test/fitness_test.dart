import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/fitness_stats.dart';
import 'package:indoor_cycling/core/ride_record.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/ui/fitness_summary.dart';
import 'package:indoor_cycling/ui/ride_history_provider.dart';

import 'fakes/in_memory_json_store.dart';

/// 10 minutes at 36 km/h = 6 km, climbing at [grade]% if given.
RideRecord ride(DateTime at, {double? grade}) => RideRecord(startedAt: at, samples: [
      RideSample(t: 0, speed: 36, grade: grade),
      RideSample(t: 600, speed: 36, grade: grade),
    ]);

void main() {
  final now = DateTime(2026, 11, 14, 12);

  test('elevation gain counts only climbing, from grade and distance', () {
    expect(ride(now, grade: 5).stats.elevationGainMeters, closeTo(300, 0.01));
    expect(ride(now, grade: -5).stats.elevationGainMeters, 0);
    expect(ride(now).stats.elevationGainMeters, 0);
  });

  test('rides saved before grade was recorded still load', () {
    final json = ride(now).toJson();
    json['samples'] = [
      for (final s in json['samples']! as List) (s as List).sublist(0, 7)
    ];
    expect(RideRecord.fromJson(json).samples.first.grade, isNull);
    expect(RideRecord.fromJson(ride(now, grade: 3).toJson()).samples.first.grade, 3);
  });

  test('last30Days spans today and the 29 days before', () {
    final days = dailyTotals([
      ride(DateTime(2026, 11, 14, 8), grade: 5), // today
      ride(DateTime(2026, 11, 14, 18)), // same day: summed
      ride(DateTime(2026, 10, 16)), // 29 days ago: in
      ride(DateTime(2026, 10, 15)), // 30 days ago: out
    ]);
    expect(days, hasLength(3));
    final t = last30Days(days, now);
    expect(t.km, closeTo(18, 0.01));
    expect(t.gainMeters, closeTo(300, 0.01));
  });

  testWidgets('summary shows totals and a dot on each riding day', (tester) async {
    final store = InMemoryJsonStore();
    for (final r in [
      ride(DateTime(2026, 11, 3), grade: 5),
      ride(DateTime(2026, 11, 9)),
    ]) {
      store.rides[r.id] = jsonEncode(r.toJson());
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [rideHistoryStoreProvider.overrideWithValue(store)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FitnessSummary(now: now)))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('12.0 km'), findsOneWidget);
    expect(find.text('300 m'), findsOneWidget);
    expect(find.byKey(const Key('dot3')), findsOneWidget);
    expect(find.byKey(const Key('dot9')), findsOneWidget);
    expect(find.byKey(const Key('dot4')), findsNothing);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.byKey(const Key('dot3')), findsNothing);
  });
}
