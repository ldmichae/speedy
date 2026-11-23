import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_scene/scene.dart';
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

import '../core/land_cover.dart';
import '../core/region_style.dart';
import '../core/route.dart';
import '../core/terrain_cache.dart';
import '../core/world_build.dart';
import '../core/world_path.dart';
import '../core/dashboard_layout.dart';
import 'compete_controller.dart';
import 'dashboard_tiles.dart';
import 'elevation_chart.dart';
import 'compete_screen.dart' show ghostColor;
import 'elevation_service.dart';
import 'route_controller.dart';
import 'route_tile.dart';
import 'trainer_controller.dart';
import 'units_controller.dart';

/// The course as a 3D road, with you and your Compete rivals riding it, under
/// a HUD: your numbers top left, the map top right, the climb along the
/// bottom.
/// Fills the space it is given. With no course it shows the route tile's
/// "Choose a route" card.
class WorldFocus extends ConsumerStatefulWidget {
  const WorldFocus({super.key});

  @override
  ConsumerState<WorldFocus> createState() => _WorldFocusState();
}

/// Metres the rider goes from the middle of the ground before it is rebuilt.
const _regroundAfter = 300.0;
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

/// OpenStreetMap land cover for the World view's scenery, each ~2 km cell
/// fetched once and kept on disk. Null on web, which has no real terrain
/// to put it on.
final landCoverProvider = Provider<LandCoverSource?>((ref) {
  if (kIsWeb) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return LandCoverSource(
      fetch: httpOverpassFetcher(client),
      cache: createTerrainCache(folder: 'landcover', extension: 'json'));
});

/// The trees of one ground square: one instanced mesh per part, so a
/// forest is a handful of draw calls.
class _Trees {
  final _bark = _matte(vm.Vector4(0.12, 0.07, 0.03, 1));
  final _leaf = _matte(); // tinted per tree
  late final trunks = InstancedMesh(
      geometry: CylinderGeometry(bottomRadius: 0.25, topRadius: 0.2, height: 2),
      material: _bark);
  late final palmTrunks = InstancedMesh(
      geometry:
          CylinderGeometry(bottomRadius: 0.16, topRadius: 0.12, height: 7),
      material: _bark);
  late final cones = InstancedMesh(
      geometry: CylinderGeometry(bottomRadius: 2.2, topRadius: 0, height: 6),
      material: _leaf);
  late final balls = InstancedMesh(
      geometry: SphereGeometry(radius: 1, segments: 12, rings: 8),
      material: _leaf);

  /// A [kind] of tree on the ground at ([x], [y], [z]), [size] times the
  /// usual, its green varied by [r] (0..1).
  void add(TreeKind kind, double x, double y, double z, double size, double r) {
    vm.Matrix4 at(double up, vm.Vector3 scale) =>
        vm.Matrix4.translation(vm.Vector3(x, y + up * size, z))
          ..scaleByVector3(scale * size);
    final one = vm.Vector3.all(1);
    switch (kind) {
      case TreeKind.conifer:
        trunks.addInstance(at(1, one));
        cones.addInstance(at(4.5, one),
            color: vm.Vector4(0.03, 0.10 + 0.04 * r, 0.03, 1));
      case TreeKind.broadleaf:
        trunks.addInstance(at(1.2, vm.Vector3(1, 1.2, 1)));
        balls.addInstance(at(4.2, vm.Vector3(2.4, 2.1, 2.4)),
            color: vm.Vector4(0.05 + 0.05 * r, 0.15 + 0.03 * r, 0.03, 1));
      case TreeKind.palm:
        palmTrunks.addInstance(at(3.5, one));
        balls.addInstance(at(7, vm.Vector3(2.6, 0.6, 2.6)),
            color: vm.Vector4(0.09, 0.20, 0.04, 1));
      case TreeKind.bush:
        balls.addInstance(at(0.6, vm.Vector3(1.3, 0.9, 1.3)),
            color: vm.Vector4(0.07 + 0.03 * r, 0.13, 0.04, 1));
    }
  }

  List<Node> nodes() => [
        for (final m in [trunks, palmTrunks, cones, balls])
          if (m.instanceCount > 0)
            Node()..addComponent(InstancedMeshComponent(m)),
      ];
}

/// The sky with a spinner and what the world is busy with, while it is
/// built.
class _WorldLoading extends StatelessWidget {
  const _WorldLoading(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final (r, g, b) = _sky;
    return ColoredBox(
      // The sky's horizon, so the reveal does not flash.
      color: Color.fromARGB(
          255,
          (math.pow(r, 1 / 2.2) * 255).round(),
          (math.pow(g, 1 / 2.2) * 255).round(),
          (math.pow(b, 1 / 2.2) * 255).round()),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(status,
                  key: const Key('worldLoading'),
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Says scenery is still on its way while the world is already ridable.
class _SceneryChip extends StatelessWidget {
  const _SceneryChip();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading scenery…'),
          ]),
        ),
      );
}

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
      // Contact shadow: a dark patch on the road under the bike, in place of
      // cast shadows (whose shaders froze the app while they compiled).
      Node(
          mesh: Mesh(
              CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 0.01),
              // Unlit: a lit one catches the sky's sheen and reads grey.
              UnlitMaterial()
                ..baseColorFactor = vm.Vector4(0.02, 0.02, 0.025, 1)))
        ..position = vm.Vector3(0, 0.015, 0.05)
        ..scale = vm.Vector3(0.22, 1, 0.7),
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
  bool _ready = false; // the engine's own resources are loaded

  /// What the world is busy with before it can be shown.
  String _status = 'Starting the 3D engine…';

  /// OpenStreetMap scenery is on its way for the ground around the rider.
  bool _sceneryLoading = false;

  WorldPath? _path;
  (RideCourse, bool)? _builtFor; // the course, and whether it had heights
  Node? _road, _ground;
  vm.Vector2? _groundAt;

  /// Bumped when the course or the ground square changes, so work still
  /// running for an old one is dropped when it finishes.
  int _courseGen = 0, _groundGen = 0;
  late final _rider = _Bike(const Color(0xFF2563EB));
  double _m = 0;

  double get _now => _clock.elapsedMicroseconds / 1e6;

  /// The road and some ground are in: the world can be shown.
  bool get _built => _road != null && _ground != null;

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
        // No cast shadows or ambient occlusion: their shaders took ~10 s to
        // compile on Windows (OpenGL), every launch, freezing the app. The
        // riders get contact shadows instead (see _Bike).
        ..directionalLight = DirectionalLight(
            direction: vm.Vector3(-0.4, -1, -0.3), intensity: 3)
        ..environmentSettings = EnvironmentSettings(
          toneMapping: ToneMappingMode.aces,
          // Hides the edge of the ground built around the rider.
          fogEnabled: true,
          fogMode: FogMode.linear,
          fogColor: vm.Vector3(r, g, b),
          fogStart: 150,
          fogEnd: groundHalf - _regroundAfter - 50,
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

  late final _asphalt = _matte(vm.Vector4(0.06, 0.06, 0.065, 1))
    ..doubleSided = true;
  late final _paint = _matte(vm.Vector4(0.9, 0.9, 0.85, 1))
    ..doubleSided = true
    ..depthLayer = 1; // lies on the asphalt
  late final _grass = _matte(); // coloured per vertex
  late final _walls = _matte()..doubleSided = true; // coloured per vertex

  /// Uploads arrays worked out off the UI thread.
  static MeshGeometry _mesh(MeshArrays a) => MeshGeometry.fromArrays(
      positions: a.positions,
      normals: a.normals,
      colors: a.colors,
      indices: a.indices,
      retainCpuData: false);

  /// Each road piece and its ends, so pieces off the ground can be hidden.
  var _pieces = <(Node, vm.Vector3, vm.Vector3)>[];

  /// Shows only the road on the ground square around ([cx], [cz]): beyond
  /// it the road would hang in the sky over nothing.
  void _showRoadNear(double cx, double cz) {
    bool on(vm.Vector3 p) =>
        (p.x - cx).abs() < groundHalf && (p.z - cz).abs() < groundHalf;
    for (final (node, a, b) in _pieces) {
      node.visible = on(a) || on(b);
    }
  }

  /// Starts building the world afresh when the course changes (or gets its
  /// heights): the road off the UI thread, then the ground around the
  /// rider. The loading card shows until both are in.
  void _syncCourse(RouteProgress p) {
    final key = (p.course, p.course.elevationAt(p.meters) != null);
    if (_builtFor == key) return;
    _builtFor = key;
    final gen = ++_courseGen;
    _groundGen++; // ground still loading for the old course is dropped
    for (final old in [_road, _ground]) {
      if (old != null) _scene.remove(old);
    }
    _road = _ground = _groundAt = null;
    _sceneryLoading = false;
    _status = 'Laying the road…';
    final path = _path = WorldPath.of(p.course);
    final start = path.at(p.meters);
    () async {
      final pieces = await compute(planRoad, path);
      if (!mounted || gen != _courseGen) return;
      _pieces = [
        for (final piece in pieces)
          (
            _group([
              Node(mesh: Mesh(_mesh(piece.asphalt), _asphalt)),
              if (piece.paint case final paint?)
                Node(mesh: Mesh(_mesh(paint), _paint)),
            ]),
            piece.from,
            piece.to,
          ),
      ];
      _scene.add(_road = _group([for (final (node, _, _) in _pieces) node]));
      setState(() => _status = 'Shaping the land…');
      _reground(_snap(start.x), _snap(start.z));
    }();
  }

  /// To the nearest 100 m, so riding back and forth does not rebuild the
  /// ground every frame.
  static double _snap(double v) => (v / 100).round() * 100.0;

  /// New ground around ([cx], [cz]) on the real terrain, dressed for the
  /// region with what OpenStreetMap says is there. The first ground goes
  /// down as soon as its heights are in; scenery that has to be fetched
  /// follows (the old ground stays meanwhile).
  Future<void> _reground(double cx, double cz) async {
    _groundAt = vm.Vector2(cx, cz);
    final gen = ++_groundGen;
    final path = _path!;
    final terrain = await _terrainAround(cx, cz);
    if (!mounted || gen != _groundGen) return; // moved on meanwhile
    final first = _ground == null;
    if (first || terrain == null) {
      await _buildGround(gen, path, cx, cz, terrain, null);
    }
    // Only a real place has land cover: not a Compete course out at sea.
    if (terrain == null || !mounted || gen != _groundGen) return;
    setState(() => _sceneryLoading = true);
    final cover = await _coverAround(cx, cz);
    if (!mounted || gen != _groundGen) return;
    setState(() => _sceneryLoading = false);
    if (cover != null || !first) {
      await _buildGround(gen, path, cx, cz, terrain, cover);
    }
  }

  /// The real heights for the ground square, or null where there are none to
  /// read (web, offline) or they are not this road's ground (Compete).
  Future<HeightGrid?> _terrainAround(double cx, double cz) async {
    final tiles = ref.read(terrainTilesProvider);
    final path = _path;
    if (tiles == null || path == null) return null;
    final x0 = cx - groundHalf, z0 = cz - groundHalf;
    try {
      final h = await tiles.elevations([
        for (var r = 0; r < groundPosts; r++)
          for (var c = 0; c < groundPosts; c++)
            path.latLngOf(x0 + c * groundCell, z0 + r * groundCell),
      ]);
      final grid = HeightGrid(x0, z0, groundCell, groundPosts,
          Float64List.fromList([for (final y in h) y - path.baseHeight]));
      return grid.fits(path.near(cx, cz, groundHalf)) ? grid : null;
    } catch (_) {
      return null; // offline or a bad tile: keep the made-up hills
    }
  }

  /// What OpenStreetMap has on the ground square, or null where it cannot
  /// be had (web, offline, the service busy): then it is generic country.
  Future<LandCover?> _coverAround(double cx, double cz) async {
    final source = ref.read(landCoverProvider);
    final path = _path;
    if (source == null || path == null) return null;
    final sw = path.latLngOf(cx - groundHalf, cz - groundHalf);
    final ne = path.latLngOf(cx + groundHalf, cz + groundHalf);
    try {
      return await source.around(
          sw.latitude, sw.longitude, ne.latitude, ne.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Works out the ground square off the UI thread, then swaps it in for
  /// the last one, unless ground [gen] has been overtaken meanwhile.
  Future<void> _buildGround(int gen, WorldPath path, double cx, double cz,
      HeightGrid? terrain, LandCover? cover) async {
    final plan = await compute(planGround,
        (path: path, cx: cx, cz: cz, terrain: terrain, cover: cover));
    if (!mounted || gen != _groundGen) return;
    final trees = _Trees();
    for (final t in plan.trees) {
      trees.add(t.kind, t.x, t.y, t.z, t.size, t.r);
    }
    final ground = _group([
      for (final tile in plan.tiles) Node(mesh: Mesh(_mesh(tile), _grass)),
      ...trees.nodes(),
      for (final b in plan.buildings) Node(mesh: Mesh(_mesh(b), _walls)),
    ]);
    final shown = _built;
    if (_ground case final old?) _scene.remove(old);
    _scene.add(_ground = ground);
    _showRoadNear(cx, cz);
    if (!shown && _built) setState(() {}); // the world can be shown now
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
    if (path == null || !_built) return;
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
    if (g != null && (vm.Vector2(at.x, at.z) - g).length > _regroundAfter) {
      _reground(_snap(at.x), _snap(at.z));
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
      fovFar: 2 * groundHalf,
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

    if (_path == null) _me.update(progress.meters, _now);
    // Meshes and materials need the engine's resources; the HUD does not,
    // so it is up from the start.
    if (_ready) {
      _syncCourse(progress);
      _syncRivals(standings);
    }

    final surface = Theme.of(context).colorScheme.surface;
    final profile = progress.course.stage(progress.stage).elevation;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        const pad = 8.0, gap = 6.0, profileHeight = 84.0;
        final bottom = profile == null ? pad : profileHeight + 2 * pad;
        // Metrics fill the height above the profile, within reason: 5.75
        // units of rows (power 1.5, three rows of two 1, ERG 1.25).
        final unit =
            ((box.maxHeight - bottom - pad - 4 * gap) / 5.75).clamp(40.0, 72.0);
        Widget tile(TileKind k, double units) =>
            SizedBox(height: unit * units, child: DashboardTile(kind: k));
        Widget pair(TileKind a, TileKind b) => Row(children: [
              Expanded(child: tile(a, 1)),
              const SizedBox(width: gap),
              Expanded(child: tile(b, 1)),
            ]);
        // Narrow: no room for the map beside the metrics; its label stays.
        final showMap = box.maxWidth >= 640;
        return Stack(children: [
          Positioned.fill(
            // Built off the UI thread behind a card saying what is going on;
            // shown once the road and ground are in and shaders compiled
            // (in slices, so the app keeps answering meanwhile).
            child: _ready && _built
                ? SceneView(_scene,
                    cameraBuilder: _camera,
                    onTick: _tick,
                    maxFrameRate: 60,
                    warmUp: true,
                    revealMinDuration: const Duration(milliseconds: 300),
                    loadingBuilder: (_, __) =>
                        const _WorldLoading('Getting the world ready…'))
                : _WorldLoading(_status),
          ),
          if (_ready && _built && _sceneryLoading)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + pad,
              child: const Center(child: _SceneryChip()),
            ),
          Positioned(
            top: pad,
            left: pad,
            width: (box.maxWidth * 0.24).clamp(190.0, 280.0),
            child: Column(children: [
              for (final (i, row) in [
                tile(TileKind.powerAvg, 1.5),
                pair(TileKind.cadence, TileKind.speed),
                pair(TileKind.heartRate, TileKind.distance),
                pair(TileKind.time, TileKind.energy),
                tile(TileKind.ergTarget, 1.25),
              ].indexed) ...[
                if (i > 0) const SizedBox(height: gap),
                row,
              ],
            ]),
          ),
          if (showMap)
            Positioned(
              top: pad,
              right: pad,
              width: (box.maxWidth * 0.3).clamp(220.0, 380.0),
              height: (box.maxHeight * 0.4).clamp(160.0, 300.0),
              child: const RouteMapTile(elevation: MapElevation.none),
            )
          else
            Positioned(
              top: pad,
              right: pad,
              width: box.maxWidth * 0.4,
              child: Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                        RouteMapTile.label(
                            progress, ref.watch(rideUnitsProvider)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
          if (profile != null)
            Positioned(
              left: pad,
              right: pad,
              bottom: pad,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  // You, and the ghosts in their race colours, on the stage.
                  child: ElevationChart(
                    profile: profile,
                    height: profileHeight,
                    riderMeters: progress.stageMeters,
                    markers: [
                      for (final (i, s) in standings.indexed)
                        (s.meters, ghostColor(i)),
                    ],
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}
