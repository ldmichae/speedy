import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_export.dart';
import 'package:indoor_cycling/core/ride_record.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/rider_profile.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/ui/history_screen.dart';
import 'package:indoor_cycling/ui/preferences_screen.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';
import 'package:indoor_cycling/ui/ride_history_provider.dart';
import 'package:indoor_cycling/ui/rider_profile_controller.dart';
import 'package:indoor_cycling/ui/units_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/in_memory_json_store.dart';

RideRecord ride(DateTime at, {double? kcal}) => RideRecord(
      startedAt: at,
      kcal: kcal,
      samples: const [
        RideSample(t: 0, target: 200, power: 200, speed: 36),
        RideSample(t: 60, target: 200, power: 200, speed: 36),
        RideSample(t: 120, target: 200, power: 200, speed: 36),
      ],
    );

InMemoryJsonStore storeWith(List<RideRecord> rides) {
  final store = InMemoryJsonStore();
  for (final r in rides) {
    store.rides[r.id] = jsonEncode(r.toJson());
  }
  return store;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('history provider', () {
    test('lists newest first and skips unreadable records', () async {
      final store = storeWith([
        ride(DateTime(2026, 11, 1)),
        ride(DateTime(2026, 11, 9)),
      ])
        ..rides['bad'] = '{not json'
        ..rides['old'] = '{"v":0}';
      final c = ProviderContainer(
          overrides: [rideHistoryStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);

      final rides = await c.read(rideHistoryProvider.future);

      expect(rides.map((r) => r.startedAt),
          [DateTime(2026, 11, 9), DateTime(2026, 11, 1)]);
    });
  });

  group('saving a ride', () {
    late InMemoryJsonStore store;
    late List<(int, DateTime, RideFormat)> exports;
    Object? exportFailure;
    late ProviderContainer c;

    setUp(() {
      store = InMemoryJsonStore();
      exports = [];
      exportFailure = null;
      c = ProviderContainer(overrides: [
        rideHistoryStoreProvider.overrideWithValue(store),
        rideExporterProvider.overrideWithValue((samples, started, format) async {
          if (exportFailure != null) throw exportFailure!;
          exports.add((samples.length, started, format));
          return '/rides/x.${format.ext}';
        }),
      ]);
      addTearDown(c.dispose);
    });

    test('writes a history record with calories, then exports', () async {
      c.read(riderProfileProvider.notifier).update(const RiderProfile(
          heightCm: 180, weightKg: 80, age: 30, sex: Sex.male));
      final rec = c.read(recorderProvider.notifier)..start();

      final path = await rec.save();

      expect(path, endsWith('.fit')); // default format
      expect(exports.single.$1, 1);
      expect(store.rides, hasLength(1));
      final saved = RideRecord.fromJson(
          jsonDecode(store.rides.values.single) as Map<String, Object?>);
      expect(saved.kcal, isNotNull);
      expect(saved.startedAt, exports.single.$2);
      expect(c.read(recorderProvider).status, RecStatus.idle);
      expect(await c.read(rideHistoryProvider.future), hasLength(1));
    });

    test('calories are blank without a complete profile', () async {
      final rec = c.read(recorderProvider.notifier)..start();
      await rec.save();

      final saved = RideRecord.fromJson(
          jsonDecode(store.rides.values.single) as Map<String, Object?>);
      expect(saved.kcal, isNull);
    });

    test('a failed export keeps the recording; retrying overwrites history',
        () async {
      final rec = c.read(recorderProvider.notifier)..start();
      exportFailure = StateError('disk full');

      await expectLater(rec.save(), throwsA(isA<StateError>()));
      expect(c.read(recorderProvider).status, RecStatus.recording);
      expect(store.rides, hasLength(1));

      exportFailure = null;
      await rec.save();
      expect(store.rides, hasLength(1)); // same id, not a duplicate
      expect(c.read(recorderProvider).status, RecStatus.idle);
    });

    test('stopping with nothing recorded discards without asking', () {
      final rec = c.read(recorderProvider.notifier);
      expect(rec.requestStop(), isNull);
      expect(c.read(recorderProvider).status, RecStatus.idle);
    });

    test('keep riding resumes only a ride that was running', () async {
      final rec = c.read(recorderProvider.notifier)..start();
      var summary = rec.requestStop()!;
      expect(c.read(recorderProvider).status, RecStatus.paused);
      await rec.finish(StopChoice.keepGoing, summary);
      expect(c.read(recorderProvider).status, RecStatus.recording);

      rec.pause();
      summary = rec.requestStop()!;
      await rec.finish(StopChoice.keepGoing, summary);
      expect(c.read(recorderProvider).status, RecStatus.paused);
    });

    test('finish saves or discards', () async {
      final rec = c.read(recorderProvider.notifier)..start();
      final summary = rec.requestStop()!;
      expect(await rec.finish(StopChoice.save, summary), endsWith('.fit'));
      expect(store.rides, hasLength(1));

      rec.start();
      await rec.finish(StopChoice.discard, rec.requestStop()!);
      expect(c.read(recorderProvider).status, RecStatus.idle);
      expect(store.rides, hasLength(1));
    });
  });

  group('screens', () {
    Future<void> open(WidgetTester tester, Widget home, List<RideRecord> rides) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          rideHistoryStoreProvider.overrideWithValue(storeWith(rides)),
        ],
        child: MaterialApp(home: home),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('list cards show time, distance, power and energy',
        (tester) async {
      await open(tester, const HistoryScreen(), [
        ride(DateTime(2026, 11, 13, 14, 5), kcal: 87.4),
        ride(DateTime(2026, 11, 12, 9, 30)), // no profile at the time
      ]);

      expect(find.text('Fri 13 Nov 2026 · 14:05'), findsOneWidget);
      expect(find.text('Thu 12 Nov 2026 · 09:30'), findsOneWidget);
      expect(find.text('02:00'), findsNWidgets(2)); // total time
      expect(find.text('1.2 km'), findsNWidgets(2));
      expect(find.text('200 W'), findsNWidgets(2));
      expect(find.text('87 kcal'), findsOneWidget);
      expect(find.text('— kcal'), findsOneWidget); // unknown
      // newest first
      expect(tester.getTopLeft(find.text('Fri 13 Nov 2026 · 14:05')).dy,
          lessThan(tester.getTopLeft(find.text('Thu 12 Nov 2026 · 09:30')).dy));
    });

    testWidgets('empty history says so', (tester) async {
      await open(tester, const HistoryScreen(), []);
      expect(find.textContaining('No rides yet'), findsOneWidget);
    });

    testWidgets('tapping a ride opens the chart detail', (tester) async {
      await open(tester, const HistoryScreen(), [
        ride(DateTime(2026, 11, 13, 14, 5), kcal: 87.4),
      ]);

      await tester.tap(find.text('Fri 13 Nov 2026 · 14:05'));
      await tester.pumpAndSettle();

      expect(find.byType(RideDetailScreen), findsOneWidget);
      expect(find.byType(RideChart), findsOneWidget);
      expect(find.text('ERG target'), findsOneWidget); // metric chip
      expect(find.text('5 min'), findsNothing); // window picker is live-only
      expect(find.text('87 kcal'), findsOneWidget);
    });
  });

  group('deleting rides', () {
    Future<InMemoryJsonStore> openList(
        WidgetTester tester, InMemoryJsonStore store) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [rideHistoryStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await tester.pumpAndSettle();
      return store;
    }

    final newest = DateTime(2026, 11, 13, 14, 5);
    final oldest = DateTime(2026, 11, 12, 9, 30);

    testWidgets('asks first; cancelling keeps the ride', (tester) async {
      final store =
          await openList(tester, storeWith([ride(newest), ride(oldest)]));

      await tester.tap(find.byTooltip('Delete ride').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete this ride?'), findsOneWidget);
      expect(find.textContaining('not deleted'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this ride?'), findsNothing);
      expect(find.byTooltip('Delete ride'), findsNWidgets(2));
      expect(store.rides, hasLength(2));
    });

    testWidgets('confirming removes only that ride', (tester) async {
      final store =
          await openList(tester, storeWith([ride(newest), ride(oldest)]));

      await tester.tap(find.byTooltip('Delete ride').first); // the newest
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Fri 13 Nov 2026 · 14:05'), findsNothing);
      expect(find.text('Thu 12 Nov 2026 · 09:30'), findsOneWidget);
      expect(store.rides.keys, [ride(oldest).id]);
    });

    testWidgets('deleting the last ride shows the empty state', (tester) async {
      await openList(tester, storeWith([ride(newest)]));

      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No rides yet'), findsOneWidget);
    });

    testWidgets('a failing delete keeps the ride and says why', (tester) async {
      final store = _FailingDeleteStore()
        ..rides[ride(newest).id] = jsonEncode(ride(newest).toJson());
      await openList(tester, store);

      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not delete'), findsOneWidget);
      expect(find.text('Fri 13 Nov 2026 · 14:05'), findsOneWidget);
      expect(store.rides, hasLength(1));
    });
  });

  group('deleting from the detail view', () {
    final newest = DateTime(2026, 11, 13, 14, 5);
    final oldest = DateTime(2026, 11, 12, 9, 30);

    /// Home -> history list -> detail of the ride titled [title].
    Future<void> openDetail(WidgetTester tester,
        InMemoryJsonStore store, String title) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [rideHistoryStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byType(RideDetailScreen), findsOneWidget);
    }

    testWidgets('goes back to the list when other rides remain', (tester) async {
      final store = storeWith([ride(newest), ride(oldest)]);
      await openDetail(tester, store, 'Fri 13 Nov 2026 · 14:05');

      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this ride?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(RideDetailScreen), findsNothing);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Fri 13 Nov 2026 · 14:05'), findsNothing);
      expect(find.text('Thu 12 Nov 2026 · 09:30'), findsOneWidget);
      expect(store.rides.keys, [ride(oldest).id]);
    });

    testWidgets('returns to an empty history when it was the last ride', (tester) async {
      final store = storeWith([ride(newest)]);
      await openDetail(tester, store, 'Fri 13 Nov 2026 · 14:05');

      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(RideDetailScreen), findsNothing);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.textContaining('No rides yet'), findsOneWidget);
      expect(store.rides, isEmpty);
    });

    testWidgets('cancelling stays on the detail view', (tester) async {
      final store = storeWith([ride(newest), ride(oldest)]);
      await openDetail(tester, store, 'Fri 13 Nov 2026 · 14:05');

      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(RideDetailScreen), findsOneWidget);
      expect(store.rides, hasLength(2));
    });

    testWidgets('a failing delete stays on the detail view with a message',
        (tester) async {
      final store = _FailingDeleteStore()
        ..rides[ride(newest).id] = jsonEncode(ride(newest).toJson());
      await openDetail(tester, store, 'Fri 13 Nov 2026 · 14:05');

      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(RideDetailScreen), findsOneWidget);
      expect(find.textContaining('Could not delete'), findsOneWidget);
      expect(store.rides, hasLength(1));
    });
  });

  group('units', () {
    Future<ProviderContainer> openPrefs(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: PreferencesScreen()),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    Finder unitButton(String key, String label) => find.descendant(
        of: find.byKey(Key(key)), matching: find.text(label));
    String textOf(WidgetTester tester, String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!.text;

    testWidgets('ride units are chosen separately and saved', (tester) async {
      final c = await openPrefs(tester);
      expect(c.read(rideUnitsProvider), UnitSystem.metric);

      await tester.tap(unitButton('rideUnits', 'Imperial'));
      await tester.pumpAndSettle();

      expect(c.read(rideUnitsProvider), UnitSystem.imperial);
      expect(c.read(bodyUnitsProvider), UnitSystem.metric); // independent
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rideUnits'), 'imperial');
      expect(prefs.getString('bodyUnits'), isNull);
    });

    testWidgets('body units re-display the stored profile without changing it',
        (tester) async {
      final c = await openPrefs(tester);
      c.read(riderProfileProvider.notifier).update(const RiderProfile(
          heightCm: 180, weightKg: 72.5, age: 34, sex: Sex.male));

      await tester.tap(unitButton('bodyUnits', 'Imperial'));
      await tester.pumpAndSettle();

      expect(textOf(tester, 'Height'), '5');
      expect(textOf(tester, 'Inches'), '11');
      expect(textOf(tester, 'Weight'), '159.8');
      expect(textOf(tester, 'Age'), '34');
      expect(c.read(riderProfileProvider).heightCm, 180); // untouched
      expect(c.read(riderProfileProvider).weightKg, 72.5);

      await tester.tap(unitButton('bodyUnits', 'Metric'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'Height'), '180');
      expect(textOf(tester, 'Weight'), '72.5');
    });

    testWidgets('typing imperial values stores metric', (tester) async {
      final c = await openPrefs(tester);
      await tester.tap(unitButton('bodyUnits', 'Imperial'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Height'), '6');
      await tester.enterText(find.widgetWithText(TextField, 'Inches'), '2');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '200');
      await tester.pumpAndSettle();

      final p = c.read(riderProfileProvider);
      expect(p.heightCm, 188); // 74 in
      expect(p.weightKg, closeTo(90.72, 0.01));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('riderHeightCm'), 188);
    });

    testWidgets('imperial values outside the allowed range are rejected',
        (tester) async {
      final c = await openPrefs(tester);
      await tester.tap(unitButton('bodyUnits', 'Imperial'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Height'), '9');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '20');
      await tester.pumpAndSettle();

      expect(find.text('Out of range'), findsOneWidget);
      expect(find.text('Enter 67–551'), findsOneWidget);
      expect(c.read(riderProfileProvider).heightCm, isNull);
      expect(c.read(riderProfileProvider).weightKg, isNull);
    });

    testWidgets('ride units change history distance, not the stored ride',
        (tester) async {
      final store = storeWith([ride(DateTime(2026, 11, 13, 14, 5))]);
      final c = ProviderContainer(
          overrides: [rideHistoryStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      c.read(rideUnitsProvider.notifier).set(UnitSystem.imperial);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await tester.pumpAndSettle();

      // 1.2 km: on the ride card and in the last-30-days total
      expect(find.text('0.7 mi'), findsNWidgets(2));
      expect(find.text('1.2 km'), findsNothing);
      final stored = RideRecord.fromJson(
          jsonDecode(store.rides.values.single) as Map<String, Object?>);
      expect(stored.stats.distanceKm, closeTo(1.2, 0.001));
    });

    test('stored unit choices are restored', () async {
      SharedPreferences.setMockInitialValues(
          {'rideUnits': 'imperial', 'bodyUnits': 'imperial'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(rideUnitsProvider);
      c.read(bodyUnitsProvider);
      await settle();

      expect(c.read(rideUnitsProvider), UnitSystem.imperial);
      expect(c.read(bodyUnitsProvider), UnitSystem.imperial);
    });
  });

  group('rider profile preferences', () {
    Future<ProviderContainer> openPrefs(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: PreferencesScreen()),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('entering values updates and stores the profile', (tester) async {
      final c = await openPrefs(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Height'), '180');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '72.5');
      await tester.enterText(find.widgetWithText(TextField, 'Age'), '34');
      await tester.tap(find.text('Female'));
      await tester.pumpAndSettle();

      final p = c.read(riderProfileProvider);
      expect(p.heightCm, 180);
      expect(p.weightKg, 72.5);
      expect(p.age, 34);
      expect(p.sex, Sex.female);
      expect(p.complete, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('riderHeightCm'), 180);
      expect(prefs.getDouble('riderWeightKg'), 72.5);
      expect(prefs.getInt('riderAge'), 34);
      expect(prefs.getString('riderSex'), 'female');
    });

    testWidgets('out-of-range values show an error and are not used',
        (tester) async {
      final c = await openPrefs(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Height'), '999');
      await tester.pumpAndSettle();

      expect(find.text('Enter 100–250'), findsOneWidget);
      expect(c.read(riderProfileProvider).heightCm, isNull);
    });

    test('a stored profile is restored', () async {
      SharedPreferences.setMockInitialValues({
        'riderHeightCm': 170,
        'riderWeightKg': 65.0,
        'riderAge': 41,
        'riderSex': 'male',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(riderProfileProvider);
      await settle();

      final p = c.read(riderProfileProvider);
      expect(p.heightCm, 170);
      expect(p.weightKg, 65.0);
      expect(p.age, 41);
      expect(p.sex, Sex.male);
    });
  });
}

class _FailingDeleteStore extends InMemoryJsonStore {
  @override
  Future<void> delete(String id) async => throw StateError('disk is read-only');
}
