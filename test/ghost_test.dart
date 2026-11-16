import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/course.dart';
import 'package:indoor_cycling/core/ghost.dart';
import 'package:indoor_cycling/ui/compete_controller.dart';

import 'fakes/in_memory_json_store.dart';

// 10 m/s: 100 m every 10 s, 200 m in all.
Ghost ghost({String id = 'g', String course = 'c', double secs = 20, bool mine = false}) =>
    Ghost(
        id: id,
        course: course,
        name: 'Sam',
        t: [0, secs / 2, secs],
        d: [0, 100, 200],
        mine: mine);

void main() {
  group('ghost', () {
    test('distance and time interpolate and clamp', () {
      final g = ghost();
      expect(g.distanceAt(5), closeTo(50, 1e-9));
      expect(g.distanceAt(99), 200);
      expect(g.timeAt(150), closeTo(15, 1e-9));
      expect(g.timeAt(201), isNull);
    });

    test("gap: ahead in seconds, behind, then past the ghost's end", () {
      final g = ghost();
      final ahead = gapTo(g, elapsed: 10, riderMeters: 120);
      expect(ahead.meters, closeTo(20, 1e-9));
      expect(ahead.seconds, closeTo(2, 1e-9));
      expect(gapText(ahead), '2 s ahead');
      expect(gapText(gapTo(g, elapsed: 10, riderMeters: 80)), '2 s behind');
      final past = gapTo(g, elapsed: 30, riderMeters: 250);
      expect(past.seconds, isNull);
      expect(gapText(past), '50 m ahead');
    });

    test('file round-trips and rejects bad data', () {
      final back = Ghost.fromJson(ghost(mine: true).toJson())!;
      expect((back.course, back.meters, back.mine), ('c', 200, true));
      Map<String, Object?> f(Object pts) =>
          {'v': 1, 'id': 'x', 'course': 'c', 'name': 'n', 'pts': pts};
      for (final bad in [
        null,
        {'v': 2},
        {'v': 1, 'id': 'x', 'name': 'n', 'pts': [[0, 0], [5, 10]]}, // no course
        f([[0, 0]]),
        f([[0, 0], [5, 10], [4, 20]]),
        f([[0, 0], ['a', 1]]),
        f([[0, 0], [5, 0]]),
      ]) {
        expect(Ghost.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('a trace ends exactly on the line, at the moment it was crossed', () {
      final tr = GhostTrace(100)
        ..add(5, 40)
        ..add(5, 50) // same second: ignored
        ..add(10, 80)
        ..add(12, 120) // crosses 100 m halfway through this tick
        ..add(14, 140); // after the finish: ignored
      expect(tr.finished, isTrue);
      expect(tr.d, [0, 40, 80, 100]);
      expect(tr.t.last, closeTo(11, 1e-9));
    });
  });

  group('catalog', () {
    test('ids are unique and each course rides its own grades', () {
      expect(courses.map((c) => c.id).toSet(), hasLength(courses.length));
      for (final c in courses) {
        expect(c.route.lengthMeters, closeTo(c.lengthMeters, 1), reason: c.id);
        expect(identical(c.route, c.route), isTrue);
      }
      final drag = courseById('long-drag-v1')!.route;
      expect(drag.gradeAt(4000), closeTo(6, 0.1)); // mid-climb
      expect(drag.gradeAt(200), closeTo(0, 0.1));
    });
  });

  group('ghosts store', () {
    late ProviderContainer c;
    late InMemoryJsonStore store;
    final course = courses.first;
    final len = course.route.lengthMeters;
    Ghost mine(String id, double secs) => Ghost(
        id: id, course: course.id, name: id, t: [0, secs], d: [0, len], mine: true);

    setUp(() async {
      store = InMemoryJsonStore();
      c = ProviderContainer(
          overrides: [ghostStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      await c.read(ghostsProvider.future);
    });

    test('keeps only your best and your latest ride of a course', () async {
      final n = c.read(ghostsProvider.notifier);
      await n.addMine(mine('a', 900));
      await n.addMine(mine('b', 800)); // new best; a was neither
      await n.addMine(mine('c', 850)); // latest, slower
      expect(store.rides.keys.toSet(), {'b', 'c'});
      final all = c.read(ghostsProvider).value!;
      expect(bestOf(all, course.id)!.id, 'b');
      expect(ghostLabel(all.firstWhere((g) => g.id == 'c'), all), 'Your last ride');
    });

    test('import: never yours, and only for a known course it finishes',
        () async {
      final n = c.read(ghostsProvider.notifier);
      final g = await n.import(jsonEncode(mine('x', 700).toJson()));
      expect(g.mine, isFalse);
      expect(store.rides.keys, ['x']);
      for (final bad in [
        '{not json',
        jsonEncode(ghost().toJson()), // course 'c' is not in the catalog
        jsonEncode(ghost(course: course.id).toJson()), // stops at 200 m
      ]) {
        await expectLater(n.import(bad), throwsFormatException);
      }
      expect(store.rides.keys, ['x']);
    });
  });

  group('effort', () {
    Ghost effortful() => Ghost(
        id: 'e',
        course: 'c',
        name: 'Sam',
        t: [0, 10, 20],
        d: [0, 100, 200],
        power: [null, 250, 300],
        hr: [null, 150, 160],
        kg: 75);

    test('is read as last recorded at or before a moment', () {
      final g = effortful();
      expect(g.effortAt(-1), (watts: null, bpm: null));
      expect(g.effortAt(9.9), (watts: null, bpm: null));
      expect(g.effortAt(10), (watts: 250, bpm: 150));
      expect(g.effortAt(15), (watts: 250, bpm: 150));
      expect(g.effortAt(99), (watts: 300, bpm: 160));
    });

    test('round-trips; old two-column files still load; nonsense is dropped',
        () {
      final back = Ghost.fromJson(effortful().toJson())!;
      expect(back.power, [null, 250, 300]);
      expect(back.hr, [null, 150, 160]);
      expect(back.kg, 75);

      final old = Ghost.fromJson(ghost().toJson())!; // no effort at all
      expect(old.power, [null, null, null]);
      expect(old.kg, isNull);
      expect(ghost().toJson()['pts'], [[0, 0], [10, 100], [20, 200]]);

      final odd = Ghost.fromJson({
        'v': 1, 'id': 'x', 'course': 'c', 'name': 'n', 'kg': 900,
        'pts': [[0, 0, -5, 'fast'], [5, 10, 99999, 300], [9, 20, 200.4, 140]],
      })!;
      expect(odd.power, [null, null, 200]);
      expect(odd.hr, [null, null, 140]);
      expect(odd.kg, isNull);
    });

    test('a trace keeps the effort of each point, including the finish', () {
      final tr = GhostTrace(100)
        ..add(5, 50, watts: 200, bpm: 140)
        ..add(10, 120, watts: 220, bpm: 145);
      expect(tr.power, [null, 200, 220]);
      expect(tr.hr, [null, 140, 145]);
    });

    test('text leaves out what is not known', () {
      expect(effortText(245, 162, 72), '245 W · 3.4 W/kg · 162 bpm');
      expect(effortText(245, null, null), '245 W');
      expect(effortText(null, 150, 72), '150 bpm');
      expect(effortText(null, null, 72), isNull);
    });
  });
}
