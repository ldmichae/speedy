import 'dart:convert';

/// Something that can be placed on the workout dashboard.
enum TileKind {
  powerAvg('Power (3 s average)', span: 3, rows: 2),
  powerNow('Power'),
  cadence('Cadence'),
  speed('Speed'),
  heartRate('Heart rate'),
  time('Time'),
  distance('Distance', rideOnly: true),
  avgPower('Avg power', rideOnly: true),
  energy('Energy', rideOnly: true),
  ergTarget('ERG target', span: 2, minSpan: 2),
  chart('Chart', span: 3, rows: 4, minSpan: 2, minRows: 3, rideOnly: true),
  route('Route map', span: 3, rows: 4, minSpan: 2, minRows: 3, rideOnly: true);

  const TileKind(
    this.label, {
    this.span = 1,
    this.rows = 1,
    this.minSpan = 1,
    this.minRows = 1,
    this.rideOnly = false,
  });

  final String label;

  /// Size when first added: columns of a side (out of [sideColumns]), and rows.
  final int span;
  final int rows;

  /// Smallest size the content still works at.
  final int minSpan;
  final int minRows;

  /// Totals and the chart mean nothing until a ride is being recorded, so
  /// they are hidden until then.
  final bool rideOnly;
}

/// The dashboard has two sides, each its own grid of this many columns.
const sideColumns = 3;
const maxTileRows = 6;

/// Widths a tile can take, in columns of its side, with their labels.
const tileWidths = <(int, String)>[
  (1, '1/3'),
  (2, '2/3'),
  (3, 'Full'),
];

enum Side { left, right }

class TileConfig {
  const TileConfig(this.kind, this.span, this.rows);

  final TileKind kind;
  final int span;
  final int rows;

  /// Same size, forced up to what [kind] needs.
  TileConfig withKind(TileKind k) => TileConfig(
        k,
        span < k.minSpan ? k.minSpan : span,
        rows < k.minRows ? k.minRows : rows,
      );

  TileConfig sized({int? span, int? rows}) => TileConfig(
        kind,
        (span ?? this.span).clamp(kind.minSpan, sideColumns).toInt(),
        (rows ?? this.rows).clamp(kind.minRows, maxTileRows).toInt(),
      );
}

/// The user's dashboard: a left and a right side, each a list of tiles in
/// reading order. Each kind appears at most once across both.
class DashboardLayout {
  const DashboardLayout({required this.left, required this.right});

  final List<TileConfig> left;
  final List<TileConfig> right;

  /// What you glance at and steer with on the left: power, the ERG controls
  /// directly beneath it, then cadence, speed and heart rate. The ride so far
  /// on the right: the chart over the distance, average power and energy
  /// totals. The right is hidden until recording, and elapsed time lives in
  /// the Record bar, so the Time tile is left out (it can be added back).
  static const standard = DashboardLayout(
    left: [
      TileConfig(TileKind.powerAvg, 3, 2),
      TileConfig(TileKind.ergTarget, 2, 1),
      TileConfig(TileKind.cadence, 1, 1),
      TileConfig(TileKind.speed, 1, 1),
      TileConfig(TileKind.heartRate, 1, 1),
      TileConfig(TileKind.time, 1, 1),
    ],
    right: [
      TileConfig(TileKind.chart, 3, 3),
      TileConfig(TileKind.distance, 1, 1),
      TileConfig(TileKind.avgPower, 1, 1),
      TileConfig(TileKind.energy, 1, 1),
    ],
  );

  List<TileConfig> side(Side s) => s == Side.left ? left : right;

  List<TileConfig> get all => [...left, ...right];

  /// Kinds that are not on the dashboard, available to add.
  List<TileKind> get unplaced => [
        for (final k in TileKind.values)
          if (sideOf(k) == null) k
      ];

  Side? sideOf(TileKind k) => left.any((t) => t.kind == k)
      ? Side.left
      : right.any((t) => t.kind == k)
          ? Side.right
          : null;

  DashboardLayout _with(Side s, List<TileConfig> tiles) => s == Side.left
      ? DashboardLayout(left: tiles, right: right)
      : DashboardLayout(left: left, right: tiles);

  /// Puts [kind] on [to] at [index], counted among that side's other tiles
  /// (it may come from the other side). Tiles after it are pushed along to
  /// the next open slots when placed.
  DashboardLayout moveTo(TileKind kind, Side to, int index) {
    final from = sideOf(kind);
    if (from == null) return this;
    final moved = side(from).firstWhere((t) => t.kind == kind);
    final withoutKind = DashboardLayout(
      left: [for (final t in left) if (t.kind != kind) t],
      right: [for (final t in right) if (t.kind != kind) t],
    );
    final target = [...withoutKind.side(to)];
    target.insert(index.clamp(0, target.length).toInt(), moved);
    return withoutKind._with(to, target);
  }

  DashboardLayout resize(TileKind k, {int? span, int? rows}) {
    final s = sideOf(k);
    if (s == null) return this;
    return _with(s, [
      for (final t in side(s)) t.kind == k ? t.sized(span: span, rows: rows) : t
    ]);
  }

  /// Makes the tile showing [current] show [other] instead. If [other] is
  /// already on the dashboard (either side) the two swap, so no metric
  /// appears twice. Each tile keeps its own slot and size, raised to what its
  /// new content needs.
  DashboardLayout showInstead(TileKind current, TileKind other) {
    if (sideOf(current) == null || current == other) return this;
    TileConfig swap(TileConfig t) => t.kind == current
        ? t.withKind(other)
        : t.kind == other
            ? t.withKind(current)
            : t;
    return DashboardLayout(
      left: [for (final t in left) swap(t)],
      right: [for (final t in right) swap(t)],
    );
  }

  DashboardLayout remove(TileKind k) => DashboardLayout(
        left: [for (final t in left) if (t.kind != k) t],
        right: [for (final t in right) if (t.kind != k) t],
      );

  /// Adds [k] at the end of whichever side is currently shorter.
  DashboardLayout add(TileKind k) {
    if (sideOf(k) != null) return this;
    final s = usedRows(right) < usedRows(left) ? Side.right : Side.left;
    return _with(s, [...side(s), TileConfig(k, k.span, k.rows)]);
  }

  String toJson() {
    List<Map<String, Object>> enc(List<TileConfig> ts) => [
          for (final t in ts) {'k': t.kind.name, 's': t.span, 'r': t.rows}
        ];
    return jsonEncode({'left': enc(left), 'right': enc(right)});
  }

  /// Null if [json] is missing or unusable (including layouts saved by older
  /// versions). Unknown or repeated kinds are skipped and sizes are brought
  /// into range, so a damaged value never breaks the dashboard.
  static DashboardLayout? fromJson(String? json) {
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, Object?>;
      final seen = <TileKind>{};
      List<TileConfig> dec(Object? list) {
        final out = <TileConfig>[];
        for (final e in (list! as List).cast<Map<String, Object?>>()) {
          final kind = TileKind.values.where((k) => k.name == e['k']).firstOrNull;
          if (kind == null || !seen.add(kind)) continue;
          out.add(TileConfig(kind, 1, 1)
              .sized(span: e['s']! as int, rows: e['r']! as int));
        }
        return out;
      }

      final layout = DashboardLayout(left: dec(data['left']), right: dec(data['right']));
      return layout.all.isEmpty ? null : layout;
    } catch (_) {
      return null;
    }
  }
}

class Placement {
  const Placement(this.col, this.row, this.span, this.rows);
  final int col, row, span, rows;
}

/// Rows a side takes up once its [tiles] are placed.
int usedRows(List<TileConfig> tiles) => tiles.isEmpty
    ? 0
    : placeTiles(tiles)
        .map((p) => p.row + p.rows)
        .reduce((a, b) => a > b ? a : b);

/// Puts each tile, in order, at the first free spot at or after the previous
/// tile's position, scanning left to right then top to bottom (like a sparse
/// CSS grid). A tile therefore never lands before the one ahead of it, so
/// reading order and position always agree, and a tile that does not fit is
/// pushed on to the next open slot. Returns one placement per tile, in the
/// same order. Spans wider than the grid are narrowed to fit.
List<Placement> placeTiles(List<TileConfig> tiles, {int columns = sideColumns}) {
  final taken = <List<bool>>[];
  bool free(int row, int col, int span, int rows) {
    for (var r = row; r < row + rows && r < taken.length; r++) {
      for (var c = col; c < col + span; c++) {
        if (taken[r][c]) return false;
      }
    }
    return true;
  }

  final out = <Placement>[];
  var cursorRow = 0, cursorCol = 0;
  for (final t in tiles) {
    final span = t.span.clamp(1, columns).toInt();
    Placement? placed;
    for (var row = cursorRow; placed == null; row++) {
      for (var col = row == cursorRow ? cursorCol : 0; col + span <= columns; col++) {
        if (free(row, col, span, t.rows)) {
          placed = Placement(col, row, span, t.rows);
          break;
        }
      }
    }
    cursorRow = placed.row;
    cursorCol = placed.col;
    while (taken.length < placed.row + placed.rows) {
      taken.add(List.filled(columns, false));
    }
    for (var r = placed.row; r < placed.row + placed.rows; r++) {
      for (var c = placed.col; c < placed.col + placed.span; c++) {
        taken[r][c] = true;
      }
    }
    out.add(placed);
  }
  return out;
}

/// Where in a side's reading order to put [dragged] so that, once placed, it
/// lands nearest the grid cell ([col], [row]). Tiles it collides with are
/// pushed to the next open slots. Where several positions put it equally
/// near, the one that moves the other tiles least wins. [others] are that
/// side's tiles without [dragged]; the result is an index among them, for
/// [DashboardLayout.moveTo].
int insertionIndexFor(List<TileConfig> others, TileConfig dragged, int col, int row,
    {int columns = sideColumns}) {
  final resting = placeTiles(others, columns: columns);
  var best = 0;
  var bestScore = double.infinity;
  var bestDisplacement = double.infinity;
  for (var k = 0; k <= others.length; k++) {
    final order = [...others.sublist(0, k), dragged, ...others.sublist(k)];
    final placed = placeTiles(order, columns: columns);
    final p = placed[k];
    final score = ((p.row - row) * (p.row - row) + (p.col - col) * (p.col - col)).toDouble();

    // How far the other tiles are pushed from where they sit without it.
    var displacement = 0.0;
    for (var i = 0; i < others.length; i++) {
      final q = placed[i < k ? i : i + 1];
      displacement += (q.row - resting[i].row).abs() + (q.col - resting[i].col).abs();
    }

    if (score < bestScore || (score == bestScore && displacement < bestDisplacement)) {
      best = k;
      bestScore = score;
      bestDisplacement = displacement;
    }
  }
  return best;
}
