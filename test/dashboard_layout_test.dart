import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/dashboard_layout.dart';
import 'package:indoor_cycling/ui/dashboard_layout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const standard = DashboardLayout.standard;

List<TileKind> kinds(List<TileConfig> tiles) => [for (final t in tiles) t.kind];
List<TileKind> allKinds(DashboardLayout l) => kinds(l.all);
TileConfig tile(DashboardLayout l, TileKind k) =>
    l.all.firstWhere((t) => t.kind == k);

/// Placements for one side of [l], keyed by kind; [show] drops tiles first
/// (e.g. the ride-only ones, as before recording).
Map<TileKind, Placement> place(DashboardLayout l, Side side,
    {bool Function(TileConfig)? show}) {
  final tiles = [
    for (final t in l.side(side))
      if (show?.call(t) ?? true) t
  ];
  final p = placeTiles(tiles);
  return {for (var i = 0; i < tiles.length; i++) tiles[i].kind: p[i]};
}

/// No two placements share a cell, and all fit within the columns.
void expectNoOverlap(Iterable<Placement> ps) {
  final cells = <(int, int)>{};
  for (final p in ps) {
    expect(p.col, greaterThanOrEqualTo(0));
    expect(p.col + p.span, lessThanOrEqualTo(sideColumns));
    for (var r = p.row; r < p.row + p.rows; r++) {
      for (var c = p.col; c < p.col + p.span; c++) {
        expect(cells.add((r, c)), isTrue, reason: 'overlap at row $r col $c');
      }
    }
  }
}

(int, int) at(Placement p) => (p.row, p.col);

void main() {
  group('placeTiles (one side, three columns)', () {
    test('fills left to right, then wraps to the next row', () {
      final p = placeTiles(const [
        TileConfig(TileKind.cadence, 1, 1),
        TileConfig(TileKind.speed, 1, 1),
        TileConfig(TileKind.heartRate, 1, 1),
        TileConfig(TileKind.powerNow, 1, 1),
      ]);
      expect([for (final x in p) at(x)], [(0, 0), (0, 1), (0, 2), (1, 0)]);
    });

    test('a tall tile leaves room beside it, which later tiles fill', () {
      final p = placeTiles(const [
        TileConfig(TileKind.powerAvg, 2, 2),
        TileConfig(TileKind.cadence, 1, 1),
        TileConfig(TileKind.speed, 1, 1),
        TileConfig(TileKind.heartRate, 1, 1),
      ]);
      expect([for (final x in p) at(x)], [(0, 0), (0, 2), (1, 2), (2, 0)]);
    });

    test('a later tile never back-fills a gap ahead of an earlier one', () {
      // Col 2 is free on row 0, but the second 2-wide tile had to go down, so
      // the small tile after it stays after it instead of jumping back.
      final p = placeTiles(const [
        TileConfig(TileKind.cadence, 2, 1),
        TileConfig(TileKind.speed, 2, 1),
        TileConfig(TileKind.heartRate, 1, 1),
      ]);
      expect(at(p[1]), (1, 0));
      expect(at(p[2]), (1, 2));
      for (var i = 1; i < p.length; i++) {
        expect(p[i].row * sideColumns + p[i].col,
            greaterThan(p[i - 1].row * sideColumns + p[i - 1].col));
      }
    });

    test('a tile too wide for the end of a row moves down', () {
      final p = placeTiles(const [
        TileConfig(TileKind.cadence, 2, 1),
        TileConfig(TileKind.speed, 2, 1),
      ]);
      expect(at(p[1]), (1, 0));
    });

    test('a span wider than the grid is narrowed to fit', () {
      final p = placeTiles(const [TileConfig(TileKind.chart, 9, 3)]);
      expect(p.single.span, sideColumns);
    });

    test('an empty side places nothing and uses no rows', () {
      expect(placeTiles(const []), isEmpty);
      expect(usedRows(const []), 0);
    });

    test('usedRows is the bottom of the lowest tile', () {
      expect(usedRows(standard.left), 4); // power 2 + ERG 1 + small row 1
      expect(usedRows(standard.right), 4); // chart 3 + totals row 1
    });
  });

  group('the standard layout', () {
    test('every kind appears at most once across both sides', () {
      expect(allKinds(standard).toSet(), hasLength(standard.all.length));
    });

    test('the ERG controls sit directly under the power tile', () {
      expect(kinds(standard.left).take(2), [TileKind.powerAvg, TileKind.ergTarget]);
      final left = place(standard, Side.left);
      final power = left[TileKind.powerAvg]!;
      expect(at(left[TileKind.ergTarget]!), (power.row + power.rows, 0));
    });

    test('elapsed time is a tile, not part of the Record bar', () {
      expect(allKinds(standard), contains(TileKind.time));
      expect(standard.unplaced, [TileKind.powerNow, TileKind.route]);
    });

    test('before recording: only the left side has anything to show', () {
      bool notRideOnly(TileConfig t) => !t.kind.rideOnly;
      final left = place(standard, Side.left, show: notRideOnly);
      expect(at(left[TileKind.powerAvg]!), (0, 0));
      expect(at(left[TileKind.ergTarget]!), (2, 0));
      expect(at(left[TileKind.cadence]!), (2, 2));
      expect(at(left[TileKind.speed]!), (3, 0));
      expect(at(left[TileKind.heartRate]!), (3, 1));
      expect(at(left[TileKind.time]!), (3, 2));
      expectNoOverlap(left.values);

      // Everything on the right waits for a ride.
      expect(place(standard, Side.right, show: notRideOnly), isEmpty);
    });

    test('while recording: chart on the right over three totals', () {
      final right = place(standard, Side.right);
      expect(at(right[TileKind.chart]!), (0, 0));
      expect(at(right[TileKind.distance]!), (3, 0));
      expect(at(right[TileKind.avgPower]!), (3, 1));
      expect(at(right[TileKind.energy]!), (3, 2));
      expectNoOverlap(right.values);
      expectNoOverlap(place(standard, Side.left).values);
    });

    test('the two sides end on the same row, so neither leaves a hole', () {
      expect(usedRows(standard.left), usedRows(standard.right));
    });

    test('the two sides are independent grids', () {
      // Whatever is in one side never moves the other's tiles.
      final grown = standard.resize(TileKind.powerAvg, rows: 6);
      expect(place(grown, Side.right).values.map(at),
          place(standard, Side.right).values.map(at));
    });
  });

  group('insertionIndexFor (where a dropped tile lands on a side)', () {
    TileConfig cfg(TileKind k) => tile(standard, k);

    /// Left side's reading order after dropping [kind] at (row, col) on it.
    List<TileKind> dropOnLeft(TileKind kind, int row, int col,
        {DashboardLayout from = standard}) {
      final dragged = tile(from, kind);
      final others = [for (final t in from.left) if (t.kind != kind) t];
      final i = insertionIndexFor(others, dragged, col, row);
      return kinds(from.moveTo(kind, Side.left, i).left);
    }

    test('dropping where it already is changes nothing', () {
      final all = place(standard, Side.left);
      for (final k in [TileKind.ergTarget, TileKind.cadence, TileKind.heartRate]) {
        final p = all[k]!;
        expect(dropOnLeft(k, p.row, p.col), kinds(standard.left), reason: k.name);
      }
    });

    test('dropping a tile exactly where it sits among ties moves nothing else', () {
      // A full-width tile at the end: two insertion points land it identically,
      // and the one that leaves its neighbours alone must win.
      final l = DashboardLayout(
        left: const [
          TileConfig(TileKind.cadence, 1, 1),
          TileConfig(TileKind.speed, 1, 1),
          TileConfig(TileKind.heartRate, 1, 1),
          TileConfig(TileKind.energy, 3, 1),
        ],
        right: const [],
      );
      final p = place(l, Side.left)[TileKind.energy]!;
      expect(dropOnLeft(TileKind.energy, p.row, p.col, from: l), kinds(l.left));
    });

    test('dropping on another tile takes its slot and shoves it on', () {
      // Heart rate dropped on cadence's slot (row 2, col 2).
      final order = dropOnLeft(TileKind.heartRate, 2, 2);
      expect(order.indexOf(TileKind.heartRate), lessThan(order.indexOf(TileKind.cadence)));
      final p = place(
          DashboardLayout(left: [
            for (final k in order) tile(standard, k)
          ], right: const []),
          Side.left);
      expect(at(p[TileKind.heartRate]!), (2, 2));
      expect(at(p[TileKind.cadence]!), (3, 0));
      expect(at(p[TileKind.speed]!), (3, 1));
    });

    test('a big tile dropped on small ones pushes them out of its way', () {
      final from = standard.moveTo(TileKind.chart, Side.left, 99); // chart on the left
      final order = dropOnLeft(TileKind.chart, 4, 0, from: from);
      final l = DashboardLayout(
          left: [for (final k in order) tile(from, k)], right: const []);
      final p = place(l, Side.left);
      expect(at(p[TileKind.chart]!), (4, 0));
      expectNoOverlap(p.values);
      expect(p.length, from.left.length); // nothing lost
    });

    test('dropping at the very top-left goes first, shoving the rest', () {
      expect(dropOnLeft(TileKind.heartRate, 0, 0).first, TileKind.heartRate);
    });

    test('dropping far below the content lands in the last row, at the drop column',
        () {
      (int, int) landing(TileKind kind, int row, int col) {
        final order = dropOnLeft(kind, row, col);
        final p = place(
            DashboardLayout(
                left: [for (final k in order) tile(standard, k)], right: const []),
            Side.left);
        return at(p[kind]!);
      }

      // The last row is row 3 (the three small tiles). A drop beneath it picks
      // the slot in that row nearest the column, never a gap earlier on.
      expect(landing(TileKind.cadence, 40, 0), (3, 0));
      expect(landing(TileKind.cadence, 40, 2), (3, 2));
      expect(dropOnLeft(TileKind.cadence, 40, 2).last, TileKind.cadence);
    });

    test('dropping below a full last row starts a new row', () {
      // The right side's last row (distance, avg power, energy) is full.
      final others = [for (final t in standard.right) t];
      final i = insertionIndexFor(others, tile(standard, TileKind.cadence), 0, 40);
      expect(i, others.length); // last
      final moved = standard.moveTo(TileKind.cadence, Side.right, i);
      expect(at(place(moved, Side.right)[TileKind.cadence]!), (4, 0));
    });

    test('dropping on an empty side just puts it there', () {
      final others = <TileConfig>[];
      expect(insertionIndexFor(others, cfg(TileKind.cadence), 1, 3), 0);
    });

    test('whatever the drop, every tile is placed once with no overlaps', () {
      for (final kind in allKinds(standard)) {
        for (final side in Side.values) {
          for (final (col, row) in [(0, 0), (1, 1), (2, 3), (0, 9), (2, 30)]) {
            final dragged = tile(standard, kind);
            final others = [for (final t in standard.side(side)) if (t.kind != kind) t];
            final i = insertionIndexFor(others, dragged, col, row);
            expect(i, inInclusiveRange(0, others.length));

            final moved = standard.moveTo(kind, side, i);
            expect(allKinds(moved).toSet(), allKinds(standard).toSet(),
                reason: '${kind.name} -> ${side.name} ($col, $row)');
            expectNoOverlap(place(moved, Side.left).values);
            expectNoOverlap(place(moved, Side.right).values);
          }
        }
      }
    });
  });

  group('DashboardLayout edits', () {
    test('moveTo within a side inserts among the other tiles', () {
      var l = standard.moveTo(TileKind.heartRate, Side.left, 1);
      expect(kinds(l.left).sublist(0, 4),
          [TileKind.powerAvg, TileKind.heartRate, TileKind.ergTarget, TileKind.cadence]);

      // Later: the index counts the tiles without the one being moved.
      l = standard.moveTo(TileKind.cadence, Side.left, 3);
      expect(kinds(l.left),
          [TileKind.powerAvg, TileKind.ergTarget, TileKind.speed, TileKind.cadence, TileKind.heartRate, TileKind.time]);
    });

    test('moveTo the other side takes it off the first', () {
      final l = standard.moveTo(TileKind.cadence, Side.right, 1);
      expect(kinds(l.right).take(3), [TileKind.chart, TileKind.cadence, TileKind.distance]);
      expect(kinds(l.left), isNot(contains(TileKind.cadence)));
      expect(allKinds(l).toSet(), allKinds(standard).toSet());
      expect(l.sideOf(TileKind.cadence), Side.right);
    });

    test('moving keeps the tile\'s size', () {
      final l = standard.moveTo(TileKind.chart, Side.left, 0);
      expect(kinds(l.left).first, TileKind.chart);
      expect((tile(l, TileKind.chart).span, tile(l, TileKind.chart).rows), (3, 3));
    });

    test('moveTo the ends, and out-of-range indexes are clamped', () {
      expect(standard.moveTo(TileKind.chart, Side.right, 0).right.first.kind, TileKind.chart);
      expect(standard.moveTo(TileKind.powerAvg, Side.left, 999).left.last.kind,
          TileKind.powerAvg);
      expect(standard.moveTo(TileKind.chart, Side.right, -5).right.first.kind,
          TileKind.chart);
    });

    test('a side can be emptied by moving everything off it', () {
      var l = standard;
      for (final t in standard.right) {
        l = l.moveTo(t.kind, Side.left, 0);
      }
      expect(l.right, isEmpty);
      expect(allKinds(l).toSet(), allKinds(standard).toSet());
      // And a tile can be dropped back onto the empty side.
      expect(l.moveTo(TileKind.cadence, Side.right, 0).right.single.kind,
          TileKind.cadence);
    });

    test('moving a tile that is not on the dashboard changes nothing', () {
      final without = standard.remove(TileKind.speed);
      expect(without.moveTo(TileKind.speed, Side.left, 0), same(without));
    });

    test('resizing clamps to what the content needs', () {
      var l = standard.resize(TileKind.cadence, span: 2, rows: 3);
      expect((tile(l, TileKind.cadence).span, tile(l, TileKind.cadence).rows), (2, 3));

      l = standard.resize(TileKind.ergTarget, span: 1, rows: 1);
      expect(tile(l, TileKind.ergTarget).span, TileKind.ergTarget.minSpan);
      expect(tile(l, TileKind.ergTarget).rows, TileKind.ergTarget.minRows);

      l = standard.resize(TileKind.cadence, span: 99, rows: 99);
      expect(tile(l, TileKind.cadence).span, sideColumns);
      expect(tile(l, TileKind.cadence).rows, maxTileRows);
    });

    test('resizing a tile on the right leaves the left untouched', () {
      final l = standard.resize(TileKind.chart, rows: 6);
      expect(l.left, same(standard.left));
      expect(tile(l, TileKind.chart).rows, 6);
    });

    test('showing a metric that is already placed swaps the two tiles', () {
      final l = standard.showInstead(TileKind.cadence, TileKind.speed);
      expect(kinds(l.left).sublist(2, 4), [TileKind.speed, TileKind.cadence]);
      expect(allKinds(l).toSet(), hasLength(standard.all.length)); // no repeats
    });

    test('swapping works across sides, each tile keeping its slot', () {
      final l = standard.showInstead(TileKind.cadence, TileKind.chart);
      expect(l.sideOf(TileKind.chart), Side.left);
      expect(l.sideOf(TileKind.cadence), Side.right);
      // Chart took cadence's slot (index 2 on the left); cadence took the
      // chart's (index 0 on the right).
      expect(l.left[2].kind, TileKind.chart);
      expect(l.right[0].kind, TileKind.cadence);
      // The chart needs at least 2/3 wide and 3 rows, so the small slot grows.
      expect((l.left[2].span, l.left[2].rows), (2, 3));
      // Cadence now sits in the chart's full-width, 3-row slot.
      expect((l.right[0].span, l.right[0].rows), (3, 3));
    });

    test('swapped tiles keep their own sizes', () {
      var l = standard.resize(TileKind.cadence, span: 2);
      l = l.showInstead(TileKind.cadence, TileKind.speed);
      expect(tile(l, TileKind.speed).span, 2); // the first slot, now speed
      expect(tile(l, TileKind.cadence).span, 1); // the second slot, now cadence
    });

    test('showing something not placed replaces it', () {
      final l = standard.showInstead(TileKind.cadence, TileKind.powerNow);
      expect(allKinds(l), contains(TileKind.powerNow));
      expect(allKinds(l), isNot(contains(TileKind.cadence)));
      expect(l.unplaced, [TileKind.cadence, TileKind.route]);
    });

    test('remove and add', () {
      var l = standard.remove(TileKind.speed);
      expect(allKinds(l), isNot(contains(TileKind.speed)));
      expect(l.unplaced, [TileKind.powerNow, TileKind.speed, TileKind.route]);

      l = l.add(TileKind.speed);
      expect(l.sideOf(TileKind.speed), isNotNull);
      final side = l.side(l.sideOf(TileKind.speed)!);
      expect(side.last.kind, TileKind.speed);
      expect(side.last.span, TileKind.speed.span);

      expect(l.add(TileKind.speed), same(l)); // already there
    });

    test('a tile is added to the shorter side', () {
      // Both sides are 5 rows tall, so a tie goes left.
      expect(standard.add(TileKind.powerNow).sideOf(TileKind.powerNow), Side.left);

      final tallLeft = standard.resize(TileKind.powerAvg, rows: 6);
      expect(tallLeft.add(TileKind.powerNow).sideOf(TileKind.powerNow), Side.right);

      final tallRight = standard.resize(TileKind.chart, rows: 6);
      expect(tallRight.add(TileKind.powerNow).sideOf(TileKind.powerNow), Side.left);
    });

    test('an empty dashboard can have everything added back', () {
      var l = standard;
      for (final k in TileKind.values) {
        l = l.remove(k);
      }
      expect(l.all, isEmpty);
      expect(l.unplaced, TileKind.values);
      for (final k in TileKind.values) {
        l = l.add(k);
      }
      expect(allKinds(l).toSet(), TileKind.values.toSet());
      expectNoOverlap(place(l, Side.left).values);
      expectNoOverlap(place(l, Side.right).values);
      // Both sides got some, rather than everything piling onto one.
      expect(l.left, isNotEmpty);
      expect(l.right, isNotEmpty);
    });
  });

  group('persistence', () {
    test('JSON round-trips both sides, order and sizes', () {
      final l = standard
          .moveTo(TileKind.chart, Side.left, 0)
          .moveTo(TileKind.cadence, Side.right, 1)
          .resize(TileKind.speed, span: 2, rows: 2)
          .remove(TileKind.energy);
      final back = DashboardLayout.fromJson(l.toJson())!;
      expect(kinds(back.left), kinds(l.left));
      expect(kinds(back.right), kinds(l.right));
      expect([for (final t in back.all) (t.span, t.rows)],
          [for (final t in l.all) (t.span, t.rows)]);
    });

    test('an empty side survives the round trip', () {
      var l = standard;
      for (final t in standard.right) {
        l = l.moveTo(t.kind, Side.left, 0);
      }
      final back = DashboardLayout.fromJson(l.toJson())!;
      expect(back.right, isEmpty);
      expect(back.left, hasLength(standard.all.length));
    });

    test('unusable input gives null', () {
      expect(DashboardLayout.fromJson(null), isNull);
      expect(DashboardLayout.fromJson('not json'), isNull);
      expect(DashboardLayout.fromJson('{}'), isNull);
      expect(DashboardLayout.fromJson('{"left":[],"right":[]}'), isNull);
      expect(DashboardLayout.fromJson('{"left":[{"k":"nope","s":1,"r":1}],"right":[]}'),
          isNull);
    });

    test('a layout saved by the old single-grid version is ignored', () {
      expect(DashboardLayout.fromJson('[{"k":"speed","s":4,"r":1}]'), isNull);
    });

    test('unknown kinds and repeats are skipped; sizes brought into range', () {
      final l = DashboardLayout.fromJson('{"left":['
          '{"k":"speed","s":99,"r":0},'
          '{"k":"future-metric","s":1,"r":1},'
          '{"k":"speed","s":1,"r":1}],'
          '"right":[{"k":"chart","s":1,"r":1},{"k":"speed","s":1,"r":1}]}')!;
      expect(kinds(l.left), [TileKind.speed]);
      expect(kinds(l.right), [TileKind.chart]); // speed already used on the left
      expect((tile(l, TileKind.speed).span, tile(l, TileKind.speed).rows), (3, 1));
      expect(tile(l, TileKind.chart).span, TileKind.chart.minSpan);
      expect(tile(l, TileKind.chart).rows, TileKind.chart.minRows);
    });

    test('edits are saved and restored', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(dashboardLayoutProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      c.read(dashboardLayoutProvider.notifier)
        ..moveTo(TileKind.chart, Side.left, 0)
        ..resize(TileKind.cadence, span: 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final again = ProviderContainer();
      addTearDown(again.dispose);
      again.read(dashboardLayoutProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final restored = again.read(dashboardLayoutProvider);
      expect(restored.left.first.kind, TileKind.chart);
      expect(tile(restored, TileKind.cadence).span, 2);
    });

    test('reset returns to the standard layout', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(dashboardLayoutProvider.notifier);
      n.remove(TileKind.speed);
      n.reset();
      expect(c.read(dashboardLayoutProvider).toJson(), standard.toJson());
    });

    test('a damaged stored value falls back to the standard layout', () async {
      SharedPreferences.setMockInitialValues({'dashboardLayout': '{{{'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(dashboardLayoutProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(dashboardLayoutProvider).toJson(), standard.toJson());
    });
  });
}
