import 'package:vector_math/vector_math.dart';

import 'land_cover.dart';

/// The kinds of tree the World view draws.
enum TreeKind { conifer, broadleaf, palm, bush }

double _smooth(double from, double to, double v) {
  final t = ((v - from) / (to - from)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// How the land looks at a [latitude], roughly: which trees grow where, the
/// tree and snow lines, and the colours of the ground and of buildings.
/// shortcut: latitude and altitude only, not climate; a desert where OSM
/// maps no sand still gets grass. Use a climate grid if riders notice.
class RegionStyle {
  RegionStyle(double latitude) : lat = latitude.abs();

  /// For a made-up course with no real place (Compete): mid-latitude.
  static final temperate = RegionStyle(47);

  /// Degrees from the equator.
  final double lat;

  /// Metres above sea level where trees stop: ~3800 m in the tropics,
  /// ~2000 m in the Alps, down to a few hundred in the Arctic.
  double get treeline => (3800 - 40 * lat).clamp(300.0, 3800.0);

  /// Metres above sea level with snow lying all summer.
  double get snowline => treeline + 700;

  bool get _tropical => lat < 25;

  /// Warm enough for pale walls and terracotta roofs (the Mediterranean up
  /// to the Po valley, the American south).
  bool get warm => lat < 45;

  /// How likely a tree is at [elevation] metres, as a share of what the
  /// cover allows: none above the tree line, thinning just below it.
  double treeChance(double elevation) =>
      1 - _smooth(treeline - 250, treeline, elevation);

  /// The tree at [elevation] metres given a random [r] in 0..1: palms and
  /// broadleaf in the tropics, conifers growing in towards the poles and up
  /// towards the tree line.
  TreeKind tree(double elevation, double r) {
    final conifer = [
      _smooth(38, 58, lat),
      _smooth(treeline - 900, treeline - 200, elevation),
    ].reduce((a, b) => a > b ? a : b);
    if (r < conifer) return TreeKind.conifer;
    if (_tropical && elevation < 1200 && r > 0.45) return TreeKind.palm;
    return TreeKind.broadleaf;
  }

  /// Linear RGB of [cover] at [elevation] metres; [r] in 0..1 picks among
  /// field crops, so farmland is a patchwork.
  Vector3 ground(Cover cover, double elevation, double r) {
    if (elevation > snowline || cover == Cover.snow) {
      return Vector3(0.85, 0.87, 0.9);
    }
    final grass = _tropical
        ? Vector3(0.05, 0.22, 0.04)
        : lat < 40
            ? Vector3(0.13, 0.18, 0.05) // dry summers: olive
            : lat > 58
                ? Vector3(0.06, 0.15, 0.05)
                : Vector3(0.07, 0.20, 0.04);
    final base = switch (cover) {
      Cover.grass || Cover.snow => grass,
      Cover.forest => grass * 0.55,
      Cover.scrub => Vector3(0.13, 0.16, 0.06),
      Cover.farmland => r < 0.4
          ? grass * 1.1
          : r < 0.75
              ? Vector3(0.35, 0.28, 0.10) // ripe crop
              : Vector3(0.16, 0.10, 0.05), // ploughed
      Cover.urban => Vector3(0.18, 0.17, 0.16),
      Cover.water => Vector3(0.03, 0.08, 0.14),
      Cover.wetland => Vector3(0.08, 0.14, 0.07),
      Cover.sand => Vector3(0.45, 0.38, 0.22),
      Cover.rock => Vector3(0.20, 0.19, 0.18),
    };
    // Above the tree line, grass gives way to thin alpine turf and rock.
    final alpine = _smooth(treeline - 100, treeline + 400, elevation);
    return base + (Vector3(0.17, 0.17, 0.13) - base) * alpine * 0.7;
  }

  /// Wall and roof colours (linear RGB) for a building, [r] in 0..1.
  ({Vector3 wall, Vector3 roof}) building(double r) {
    if (warm) {
      return (
        wall: [
          Vector3(0.75, 0.66, 0.48), // ochre
          Vector3(0.85, 0.82, 0.74), // whitewash
          Vector3(0.70, 0.52, 0.36), // sand
        ][(r * 3).floor().clamp(0, 2)],
        roof: Vector3(0.45, 0.15, 0.07), // terracotta
      );
    }
    return (
      wall: [
        Vector3(0.40, 0.16, 0.10), // brick
        Vector3(0.70, 0.68, 0.62), // render
        Vector3(0.55, 0.50, 0.42), // stone
      ][(r * 3).floor().clamp(0, 2)],
      roof: r < 0.5 ? Vector3(0.12, 0.12, 0.13) : Vector3(0.30, 0.12, 0.08),
    );
  }
}
