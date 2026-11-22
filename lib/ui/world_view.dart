import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/route.dart';
import '../core/world_path.dart';
import 'compete_controller.dart';
import 'compete_screen.dart' show ghostColor;
import 'elevation_service.dart';
import 'route_controller.dart';
import 'route_tile.dart';
import 'trainer_controller.dart';
import 'units_controller.dart';

/// The course as a 3D road, with you and your Compete rivals riding it.
/// Fills the space it is given. With no course it shows the route tile's
/// "Choose a route" card.
class WorldFocus extends ConsumerStatefulWidget {
  const WorldFocus({super.key});

  @override
  ConsumerState<WorldFocus> createState() => _WorldFocusState();
}

const _halfRoad = 3.0;
const _groundHalf = 900.0, _groundCell = 20.0, _regroundAfter = 300.0;
const _piece = 40, _tile = 15; // road samples, ground cells: ~400 m meshes
const _sky = (0.55, 0.70, 0.88); // horizon colour, also the fog

/// A Flutter colour as the engine's linear RGBA.
vm.Vector4 _linear(Color c) => vm.Vector4(math.pow(c.r, 2.2).toDouble(),
    math.pow(c.g, 2.2).toDouble(), math.pow(c.b, 2.2).toDouble(), 1);

/// A node holding [children] (and [mesh], if given).
Node _group(List<Node> children, {Mesh? mesh}) {
  final node = Node(mesh: mesh);
  children.forEach(node.add);
  return node;
}

PhysicallyBasedMaterial _matte([vm.Vector4? color]) => PhysicallyBasedMaterial()
  ..baseColorFactor = color ?? vm.Vector4(1, 1, 1, 1)
  ..metallicFactor = 0
  ..roughnessFactor = 0.9;

/// The rider's cadence (rpm) that their legs turn at; null with no reading.
/// Overridable so the preview can pedal without a trainer.
final riderCadenceProvider = Provider<double?>((ref) =>
    ref.watch(trainerControllerProvider.select((s) => s.latest?.cadenceRpm)));

/// Ghosts record no cadence: they pedal at this while they are moving.
const _ghostRpm = 85.0;

/// A rider on a bike, facing +z, wheels on y = 0, whose legs turn the
/// cranks at the cadence given to [pedal].
class _Bike {
  _Bike(Color color) {
    final paint = _matte(_linear(color));
    final dark = _matte(vm.Vector4(0.02, 0.02, 0.02, 1));
    final wheel = TorusGeometry(radius: 0.34, tubeRadius: 0.035);
    final upright = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2);
    final arm = CuboidGeometry(vm.Vector3(0.03, _crank, 0.03));
    _cranks = _group([
      // One arm up on the left, one down on the right, as on a real bike.
      Node(mesh: Mesh(arm, dark))..position = vm.Vector3(-0.1, _crank / 2, 0),
      Node(mesh: Mesh(arm, dark))..position = vm.Vector3(0.1, -_crank / 2, 0),
    ])
      ..position = _bracket;
    final segment = CapsuleGeometry(radius: 0.065, height: _limb - 0.13);
    for (final _ in const [0, 1]) {
      _legs.add(
          (Node(mesh: Mesh(segment, dark)), Node(mesh: Mesh(segment, dark))));
    }
    root = _group([
      for (final z in const [-0.5, 0.5])
        Node(mesh: Mesh(wheel, dark))
          ..position = vm.Vector3(0, 0.34, z)
          ..rotation = upright,
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.06, 0.06, 1.0)), paint))
        ..position = vm.Vector3(0, 0.6, 0),
      // Torso leaning over the bars.
      Node(mesh: Mesh(CapsuleGeometry(radius: 0.17, height: 0.45), paint))
        ..position = vm.Vector3(0, 1.05, 0.05)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 1.0),
      Node(mesh: Mesh(SphereGeometry(radius: 0.13), paint))
        ..position = vm.Vector3(0, 1.32, 0.42),
      _cranks,
      for (final (thigh, shin) in _legs) ...[thigh, shin],
    ]);
    pedal(0, 0);
  }

  late final Node root;
  late final Node _cranks;
  final _legs = <(Node, Node)>[];
  double _angle = 0; // left crank, radians from the top, forwards

  static const _crank = 0.17, _limb = 0.43; // metres
  static final _bracket = vm.Vector3(0, 0.30, 0);

  /// Turns the cranks [dt] seconds' worth at [rpm], legs following.
  void pedal(double rpm, double dt) {
    _angle = (_angle + rpm / 60 * 2 * math.pi * dt) % (2 * math.pi);
    _cranks.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), _angle);
    for (final (i, (thigh, shin)) in _legs.indexed) {
      final hip = vm.Vector3(i == 0 ? -0.12 : 0.12, 0.92, -0.18);
      final leg = legPose(hip, _bracket, _crank, _angle + i * math.pi,
          thigh: _limb, shin: _limb);
      _between(thigh, hip, leg.knee);
      _between(shin, leg.knee, leg.foot);
    }
  }

  /// Lays a Y-aligned capsule [node] from [a] to [b] (both at the same x).
  static void _between(Node node, vm.Vector3 a, vm.Vector3 b) {
    final d = b - a;
    node
      ..position = (a + b) * 0.5
      ..rotation =
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.atan2(d.z, d.y));
  }
}

class _WorldFocusState extends ConsumerState<WorldFocus> {
  final _scene = Scene();
  final _clock = Stopwatch()..start();
  final _me = MeterFollower();
  final _rivals = <MeterFollower>[];
  final _rivalBikes = <_Bike>[];
  double _cadence = 0;
  bool _ready = false;

  WorldPath? _path;
  (RideCourse, bool)? _builtFor; // the course, and whether it had heights
  Node? _road, _ground;
  vm.Vector2? _groundAt;
  late final _rider = _Bike(const Color(0xFF2563EB));
  double _m = 0;

  double get _now => _clock.elapsedMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    // Read every frame, so kept here rather than rebuilding the widget.
    ref.listenManual(riderCadenceProvider, (_, rpm) => _cadence = rpm ?? 0,
        fireImmediately: true);
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      final (r, g, b) = _sky;
      _scene
        ..skybox = Skybox(GradientSkySource(
            horizonColor: vm.Vector3(r, g, b),
            zenithColor: vm.Vector3(0.12, 0.32, 0.70)))
        ..directionalLight = DirectionalLight(
            direction: vm.Vector3(-0.4, -1, -0.3),
            intensity: 3,
            castsShadow: true)
        ..environmentSettings = EnvironmentSettings(
          toneMapping: ToneMappingMode.aces,
          ambientOcclusionEnabled: true,
          ambientOcclusionHalfResolution: true,
          // Hides the edge of the ground built around the rider.
          fogEnabled: true,
          fogMode: FogMode.linear,
          fogColor: vm.Vector3(r, g, b),
          fogStart: 150,
          fogEnd: _groundHalf - _regroundAfter - 50,
        )
        ..add(_rider.root);
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  /// Puts [node] at [m] metres, [lane] metres right of the centre line.
  void _place(Node node, double m, double lane) {
    final path = _path!;
    final h = path.heading(m);
    final p = path.at(m) + WorldPath.rightOf(h) * lane;
    node.lookAtFrom(p, p + h);
  }

  /// The road in pieces of [_piece] samples: with one huge mesh round the
  /// camera the engine cannot fit its depth range, and far faces flicker.
  void _buildRoad(WorldPath path) {
    final last = path.points.length - 1;
    _pieces = [
      for (var s = 0; s < last; s += _piece)
        (
          _group(_roadPiece(path, s, math.min(s + _piece, last))),
          path.points[s],
          path.points[math.min(s + _piece, last)],
        ),
    ];
    final road = _group([for (final (node, _, _) in _pieces) node]);
    if (_road case final old?) _scene.remove(old);
    _scene.add(_road = road);
  }

  /// Each road piece and its ends, so pieces off the ground can be hidden.
  var _pieces = <(Node, vm.Vector3, vm.Vector3)>[];

  /// Shows only the road on the ground square around ([cx], [cz]): beyond
  /// it the road would hang in the sky over nothing.
  void _showRoadNear(double cx, double cz) {
    bool on(vm.Vector3 p) =>
        (p.x - cx).abs() < _groundHalf && (p.z - cz).abs() < _groundHalf;
    for (final (node, a, b) in _pieces) {
      node.visible = on(a) || on(b);
    }
  }

  /// The road from sample [from] to [to]: asphalt, and the centre line.
  List<Node> _roadPiece(WorldPath path, int from, int to) {
    final asphalt = GeometryBuilder(deduplicate: false);
    void quad(
        vm.Vector3 n, vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, vm.Vector3 d) {
      // a-b along the road on one edge, c-d the matching points opposite.
      asphalt.normal(n);
      final i = asphalt.addVertex(a);
      asphalt
        ..addVertex(b)
        ..addVertex(c)
        ..addVertex(d)
        ..addTriangle(i, i + 1, i + 2)
        ..addTriangle(i + 2, i + 1, i + 3);
    }

    final up = vm.Vector3(0, 1, 0), down = vm.Vector3(0, -2, 0);
    final pts = path.points;
    for (var i = from; i < to; i++) {
      final r0 =
          WorldPath.rightOf(path.heading(i * path.step, span: path.step));
      final r1 =
          WorldPath.rightOf(path.heading((i + 1) * path.step, span: path.step));
      final l0 = pts[i] - r0 * _halfRoad, l1 = pts[i + 1] - r1 * _halfRoad;
      final x0 = pts[i] + r0 * _halfRoad, x1 = pts[i + 1] + r1 * _halfRoad;
      quad(up, l0, l1, x0, x1);
      // Sides down into the ground, so the road never floats.
      quad(-r0, l0 + down, l1 + down, l0, l1);
      quad(r0, x0, x1, x0 + down, x1 + down);
    }

    final paint = GeometryBuilder(deduplicate: false)..normal(up);
    const dash = 3.0, every = 10.0, half = 0.07;
    final end = math.min(to * path.step, path.length - dash);
    for (var m = (from * path.step / every).ceil() * every;
        m < end;
        m += every) {
      final r = WorldPath.rightOf(path.heading(m)) * half;
      final a = path.at(m), b = path.at(m + dash);
      final i = paint.addVertex(a - r);
      paint
        ..addVertex(b - r)
        ..addVertex(a + r)
        ..addVertex(b + r)
        ..addTriangle(i, i + 1, i + 2)
        ..addTriangle(i + 2, i + 1, i + 3);
    }

    return [
      Node(mesh: Mesh(asphalt.build(), _asphalt)),
      if (paint.vertexCount > 0) Node(mesh: Mesh(paint.build(), _paint)),
    ];
  }

  late final _asphalt = _matte(vm.Vector4(0.06, 0.06, 0.065, 1))
    ..doubleSided = true;
  late final _paint = _matte(vm.Vector4(0.9, 0.9, 0.85, 1))
    ..doubleSided = true
    ..depthLayer = 1; // lies on the asphalt

  late final _grass = _matte(); // coloured per vertex

  static const _n = (2 * _groundHalf) ~/ _groundCell + 1; // posts a side

  /// New ground around ([cx], [cz]) on the real terrain where it can be
  /// read. The old ground stays until the heights arrive; with none yet,
  /// made-up hills go down at once so the road is never in mid-air.
  Future<void> _reground(double cx, double cz) async {
    _groundAt = vm.Vector2(cx, cz);
    final gen = ++_groundGen;
    if (_ground == null) _buildGround(cx, cz, null);
    final terrain = await _terrainAround(cx, cz);
    if (!mounted || gen != _groundGen) return; // moved on meanwhile
    if (terrain != null || _ground == null) _buildGround(cx, cz, terrain);
  }

  int _groundGen = 0;

  /// The real heights for the ground square, or null where there are none to
  /// read (web, offline) or they are not this road's ground (Compete).
  Future<HeightGrid?> _terrainAround(double cx, double cz) async {
    final tiles = ref.read(terrainTilesProvider);
    final path = _path;
    if (tiles == null || path == null) return null;
    final x0 = cx - _groundHalf, z0 = cz - _groundHalf;
    try {
      final h = await tiles.elevations([
        for (var r = 0; r < _n; r++)
          for (var c = 0; c < _n; c++)
            path.latLngOf(x0 + c * _groundCell, z0 + r * _groundCell),
      ]);
      final grid = HeightGrid(x0, z0, _groundCell, _n,
          Float64List.fromList([for (final y in h) y - path.baseHeight]));
      return grid.fits(path.near(cx, cz, _groundHalf)) ? grid : null;
    } catch (_) {
      return null; // offline or a bad tile: keep the made-up hills
    }
  }

  /// Ground and trees in a square around ([cx], [cz]), replacing the last.
  void _buildGround(double cx, double cz, HeightGrid? terrain) {
    final road = _path!.near(cx, cz, _groundHalf + 150);
    const n = _n;
    final pos = <vm.Vector3>[], col = <vm.Vector4>[];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final x = cx - _groundHalf + c * _groundCell;
        final z = cz - _groundHalf + r * _groundCell;
        final g = groundAt(x, z, road, terrain: terrain);
        final shade = 0.8 + 0.2 * math.sin(x / 37) * math.cos(z / 29);
        col.add(g.road < 4
            ? vm.Vector4(0.18, 0.15, 0.10, 1) // verge
            : vm.Vector4(0.07 * shade, 0.20 * shade, 0.04 * shade, 1));
        pos.add(vm.Vector3(x, g.y, z));
      }
    }
    // Square tiles of [_tile] cells, not one mesh, as for the road.
    final tiles = <Node>[];
    for (var r0 = 0; r0 < n - 1; r0 += _tile) {
      for (var c0 = 0; c0 < n - 1; c0 += _tile) {
        final w = math.min(_tile, n - 1 - c0) + 1;
        final h = math.min(_tile, n - 1 - r0) + 1;
        final b = GeometryBuilder(deduplicate: false);
        for (var r = r0; r < r0 + h; r++) {
          for (var c = c0; c < c0 + w; c++) {
            b
              ..color(col[r * n + c])
              ..addVertex(pos[r * n + c]);
          }
        }
        // Wound so the surface faces up (see flutter_scene's terrain recipe).
        for (var r = 0; r < h - 1; r++) {
          for (var c = 0; c < w - 1; c++) {
            final v00 = r * w + c, v10 = v00 + 1, v01 = v00 + w, v11 = v01 + 1;
            b
              ..addTriangle(v00, v01, v10)
              ..addTriangle(v10, v01, v11);
          }
        }
        tiles.add(Node(mesh: Mesh(b.build(), _grass)));
      }
    }

    final trunks = InstancedMesh(
        geometry:
            CylinderGeometry(bottomRadius: 0.25, topRadius: 0.2, height: 2),
        material: _matte(vm.Vector4(0.12, 0.07, 0.03, 1)));
    final crowns = InstancedMesh(
        geometry: CylinderGeometry(bottomRadius: 2.2, topRadius: 0, height: 6),
        material: _matte(vm.Vector4(0.03, 0.12, 0.03, 1)));
    for (final t in treesAround(cx, cz, _groundHalf, road, terrain: terrain)) {
      vm.Matrix4 at(double y) =>
          vm.Matrix4.translation(vm.Vector3(t.x, t.y + y * t.size, t.z))
            ..scaleByVector3(vm.Vector3.all(t.size));
      trunks.addInstance(at(1));
      crowns.addInstance(at(4.5));
    }

    final ground = _group([
      ...tiles,
      Node()..addComponent(InstancedMeshComponent(trunks)),
      Node()..addComponent(InstancedMeshComponent(crowns)),
    ]);
    if (_ground case final old?) _scene.remove(old);
    _scene.add(_ground = ground);
    _showRoadNear(cx, cz);
  }

  void _syncCourse(RouteProgress p) {
    final key = (p.course, p.course.elevationAt(p.meters) != null);
    if (_builtFor == key) return;
    _builtFor = key;
    final path = _path = WorldPath.of(p.course);
    _buildRoad(path);
    // The old course's ground goes; new ground on the next frame.
    if (_ground case final old?) _scene.remove(old);
    _ground = _groundAt = null;
    _groundGen++; // and ground still loading for the old one is dropped
  }

  void _syncRivals(List<Standing> standings) {
    while (_rivalBikes.length > standings.length) {
      _scene.remove(_rivalBikes.removeLast().root);
      _rivals.removeLast();
    }
    while (_rivalBikes.length < standings.length) {
      final bike = _Bike(ghostColor(_rivalBikes.length));
      _rivalBikes.add(bike);
      _rivals.add(MeterFollower());
      _scene.add(bike.root);
    }
    for (final (i, s) in standings.indexed) {
      _rivals[i].update(s.meters, _now);
    }
  }

  /// Lanes either side of yours: 1.4 m right, 1.4 m left, 2.4 m right...
  static double _lane(int i) => (i.isEven ? 1 : -1) * (i < 2 ? 1.4 : 2.4);

  void _tick(Duration _, double dt) {
    final path = _path;
    if (path == null) return;
    final now = _now;
    _m = _me.advance(dt, now);
    _place(_rider.root, _m, 0);
    _rider.pedal(_cadence, dt);
    for (final (i, f) in _rivals.indexed) {
      final bike = _rivalBikes[i];
      _place(bike.root, f.advance(dt, now), _lane(i));
      bike.pedal(f.speed > 0.5 ? _ghostRpm : 0, dt);
    }
    final at = path.at(_m), g = _groundAt;
    if (g == null || (vm.Vector2(at.x, at.z) - g).length > _regroundAfter) {
      // Snapped, so riding back and forth does not rebuild every frame.
      _reground((at.x / 100).round() * 100.0, (at.z / 100).round() * 100.0);
    }
  }

  Camera _camera(Duration _) {
    final path = _path;
    if (path == null) return PerspectiveCamera();
    // Behind you along the road, so the camera follows it round bends.
    final eye = path.at(_m - 7)..y = math.max(path.at(_m - 7).y, path.at(_m).y);
    return PerspectiveCamera(
      fovRadiansY: 55 * vm.degrees2Radians,
      position: eye + vm.Vector3(0, 2.6, 0),
      target: path.at(_m + 12) + vm.Vector3(0, 1.2, 0),
      fovFar: 2 * _groundHalf,
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(routeProgressProvider);
    ref.listen(routeProgressProvider, (_, p) {
      if (p != null) _me.update(p.meters, _now);
    });
    final standings = ref.watch(raceStandingsProvider);
    if (progress == null) return const RouteMapTile();
    if (!_ready) return const Center(child: CircularProgressIndicator());

    if (_path == null) _me.update(progress.meters, _now);
    _syncCourse(progress);
    _syncRivals(standings);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: SceneView(_scene,
              cameraBuilder: _camera, onTick: _tick, maxFrameRate: 60),
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                    RouteMapTile.label(progress, ref.watch(rideUnitsProvider)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
