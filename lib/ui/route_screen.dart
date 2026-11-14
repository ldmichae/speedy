import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/elevation.dart';
import '../core/route.dart';
import '../core/route_service.dart';
import '../devices/trainer.dart';
import 'elevation_chart.dart';
import 'route_controller.dart';
import 'route_map.dart';
import 'trainer_controller.dart';

class RoutesButton extends StatelessWidget {
  const RoutesButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Routes',
        icon: const Icon(Icons.map_outlined),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RoutesScreen()),
        ),
      );
}

class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  Future<void> _draw(BuildContext context, WidgetRef ref) async {
    final route = await Navigator.of(context).push<SavedRoute>(
      MaterialPageRoute(builder: (_) => const RouteEditor()),
    );
    if (route != null) ref.read(routesProvider.notifier).add(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);
    final connected = ref.watch(trainerControllerProvider
        .select((s) => s.status == TrainerStatus.connected));
    return Scaffold(
      appBar: AppBar(title: const Text('Routes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _draw(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Draw a route'),
      ),
      body: routes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No routes yet. Draw one on the map, then ride it '
                    'and watch the dot move.'),
              ),
            )
          : ListView(children: [
              for (final r in routes)
                ListTile(
                  leading: r.elevation == null
                      ? const Icon(Icons.route)
                      : SizedBox(
                          width: 96,
                          child: ElevationChart(profile: r.elevation!, height: 48)),
                  title: Text(r.name),
                  subtitle: Text(routeDistanceText(r.lengthMeters) +
                      (r.elevation == null
                          ? ''
                          : ' · ↑ ${r.elevation!.climb.round()} m')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref.read(routesProvider.notifier).delete(r),
                    ),
                    if (r.elevation != null)
                      IconButton.filledTonal(
                        tooltip: connected
                            ? 'Ride with simulated climbs: the trainer '
                                'follows the road grade'
                            : 'Connect a trainer to ride',
                        icon: const Icon(Icons.terrain),
                        onPressed: connected
                            ? () {
                                ref
                                    .read(routeRunProvider.notifier)
                                    .start(r, simulate: true);
                                Navigator.of(context).pop();
                              }
                            : null,
                      ),
                    IconButton.filled(
                      tooltip: connected
                          ? 'Ride this route in ERG (starts recording)'
                          : 'Connect a trainer to ride',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: connected
                          ? () {
                              ref.read(routeRunProvider.notifier).start(r);
                              Navigator.of(context).pop();
                            }
                          : null,
                    ),
                  ]),
                ),
            ]),
    );
  }
}

/// One stretch between two clicked points. [path] is null while it loads.
class _Leg {
  _Leg(this.from, this.to);
  final LatLng from, to;
  List<LatLng>? path;
  bool snapped = true;
}

/// Click the map to add waypoints; each stretch snaps to roads. Pops the
/// finished [SavedRoute].
class RouteEditor extends ConsumerStatefulWidget {
  const RouteEditor({super.key});

  @override
  ConsumerState<RouteEditor> createState() => _RouteEditorState();
}

class _RouteEditorState extends ConsumerState<RouteEditor> {
  final _name = TextEditingController();
  final _points = <LatLng>[];
  final _legs = <_Leg>[];
  ElevationProfile? _elevation;
  bool _elevLoading = false;
  String? _elevError;

  bool get _loading => _legs.any((l) => l.path == null);
  bool get _anyStraight => _legs.any((l) => !l.snapped);
  List<LatLng> get _path => [
        for (final (i, l) in _legs.indexed)
          ...(l.path ?? [l.from, l.to]).skip(i == 0 ? 0 : 1),
      ];

  Future<void> _add(LatLng p) async {
    setState(() {
      _elevation = null;
      _points.add(p);
      if (_points.length > 1) _legs.add(_Leg(_points[_points.length - 2], p));
    });
    if (_legs.isEmpty) return;
    final leg = _legs.last;
    final (path, ok) =
        await snapOrStraight(ref.read(routeSnapperProvider), leg.from, leg.to);
    if (!mounted || !_legs.contains(leg)) return; // undone meanwhile
    setState(() {
      leg.path = path;
      leg.snapped = ok;
    });
  }

  void _undo() => setState(() {
        if (_points.isEmpty) return;
        _elevation = null;
        _points.removeLast();
        if (_legs.isNotEmpty) _legs.removeLast();
      });

  void _clear() => setState(() {
        _elevation = null;
        _points.clear();
        _legs.clear();
      });

  SavedRoute _draft() {
    final name = _name.text.trim();
    return SavedRoute(name.isEmpty ? 'Untitled route' : name, List.of(_points), _path);
  }

  /// Looks up heights for the drawn path; a failure is shown, not fatal.
  Future<void> _loadElevation() async {
    setState(() {
      _elevLoading = true;
      _elevError = null;
    });
    try {
      final e = await buildElevation(_draft(), ref.read(elevationSourceProvider));
      if (mounted) setState(() => _elevation = e);
    } catch (_) {
      if (mounted) {
        setState(() => _elevError = 'Could not load elevation. The route can '
            'still be saved without it.');
      }
    } finally {
      if (mounted) setState(() => _elevLoading = false);
    }
  }

  Future<void> _save() async {
    if (_elevation == null && !_elevLoading) await _loadElevation();
    if (!mounted) return;
    Navigator.of(context).pop(_draft().withElevation(_elevation));
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final length = path.length < 2 ? 0.0 : pathLength(path);
    final canSave = _points.length >= 2 && !_loading && !_elevLoading;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw a route'),
        actions: [
          TextButton(onPressed: canSave ? _save : null, child: const Text('Save')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: ref.read(routesProvider).lastOrNull?.path.first ??
                  const LatLng(48, 10),
              initialZoom: ref.read(routesProvider).isEmpty ? 4 : 13,
              onTap: (_, p) => _add(p),
            ),
            children: [
              ...mapBaseLayers(ref),
              if (path.length >= 2) PolylineLayer(polylines: [routeLine(path)]),
              MarkerLayer(markers: [
                for (final (i, p) in _points.indexed)
                  Marker(
                    point: p,
                    width: 24,
                    height: 24,
                    child: CircleAvatar(
                      backgroundColor: i == 0 ? Colors.green : scheme.primary,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                  ),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 12),
              Text(_loading ? 'Snapping…' : routeDistanceText(length),
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                tooltip: 'Undo last point',
                icon: const Icon(Icons.undo),
                onPressed: _points.isEmpty ? null : _undo,
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _points.isEmpty ? null : _clear,
              ),
            ]),
            Text(
              _points.isEmpty
                  ? 'Click the map to place the start, then each turn or '
                      'destination. Segments follow roads.'
                  : _anyStraight
                      ? 'Some segments could not snap to roads and are drawn '
                          'straight. Undo and try again, or keep them.'
                      : '${_points.length} points',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _anyStraight ? scheme.error : null),
            ),
            if (_elevation != null) ...[
              const SizedBox(height: 8),
              ElevationChart(profile: _elevation!, height: 90),
              Text(elevationSummary(_elevation!),
                  style: Theme.of(context).textTheme.bodySmall),
            ] else if (_points.length >= 2 && !_loading)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _elevLoading ? null : _loadElevation,
                  icon: const Icon(Icons.terrain),
                  label: Text(_elevLoading ? 'Loading elevation…' : 'Show elevation'),
                ),
              ),
            if (_elevError != null)
              Text(_elevError!, style: TextStyle(color: scheme.error)),
          ]),
        ),
      ]),
    );
  }
}
