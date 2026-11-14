import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/route.dart';
import '../core/units.dart';
import 'elevation_chart.dart';
import 'route_map.dart';
import 'units_controller.dart';

/// Shows an imported [route] and lets the rider tap where each stage ends.
/// Pops `(name, cuts)`: the tour name and the split distances in metres.
class TourSplitScreen extends ConsumerStatefulWidget {
  const TourSplitScreen({super.key, required this.route});
  final SavedRoute route;

  @override
  ConsumerState<TourSplitScreen> createState() => _TourSplitScreenState();
}

class _TourSplitScreenState extends ConsumerState<TourSplitScreen> {
  late final _name = TextEditingController(text: widget.route.name);
  final _every = TextEditingController();
  final _cuts = <double>[];

  /// Closest a new split may be to the ends or another split.
  static const _minGap = 100.0;

  /// Snaps a tap to the nearest point of the route and cuts there.
  void _tap(LatLng p) {
    final r = widget.route;
    const d = Distance();
    var best = 0, bestD = double.infinity;
    for (var i = 0; i < r.path.length; i++) {
      final m = d(p, r.path[i]);
      if (m < bestD) {
        bestD = m;
        best = i;
      }
    }
    final at = r.cumulative[best];
    if (at < _minGap ||
        at > r.lengthMeters - _minGap ||
        _cuts.any((c) => (c - at).abs() < _minGap)) {
      return;
    }
    setState(() => _cuts
      ..add(at)
      ..sort());
  }

  void _evenly(UnitSystem u) {
    final km = (double.tryParse(_every.text) ?? 0) *
        (u == UnitSystem.imperial ? kmPerMile : 1);
    if (km <= 0) return;
    final n = (widget.route.lengthMeters / (km * 1000)).ceil();
    setState(() => _cuts
      ..clear()
      ..addAll([
        for (var i = 1; i < n; i++) widget.route.lengthMeters * i / n
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final u = ref.watch(rideUnitsProvider);
    final b = [0.0, ..._cuts, r.lengthMeters];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split into stages'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, (_name.text, _cuts)),
              child: const Text('Create')),
        ],
      ),
      body: Column(children: [
        Expanded(
          flex: 3,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(r.path),
                  padding: const EdgeInsets.all(24)),
              minZoom: minMapZoom,
              maxZoom: maxMapZoom,
              onTap: (_, p) => _tap(p),
            ),
            children: [
              ...mapBaseLayers(ref),
              PolylineLayer(polylines: [routeLine(r.path)]),
              MarkerLayer(markers: [
                for (final c in _cuts)
                  Marker(
                    point: r.positionAt(c),
                    width: 20,
                    height: 20,
                    child: const Icon(Icons.flag, color: Colors.red, size: 20),
                  ),
              ]),
            ],
          ),
        ),
        if (r.elevation != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevationChart(profile: r.elevation!, height: 60),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'))),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _every,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: 'Every (${distanceUnit(u)})'),
                onSubmitted: (_) => _evenly(u),
              ),
            ),
            TextButton(
                onPressed: () => _evenly(u), child: const Text('Split evenly')),
          ]),
        ),
        Expanded(
          flex: 2,
          child: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                  'Tap the route to end a stage there. '
                  '${routeDistanceText(r.lengthMeters, u)} in ${b.length - 1} stage'
                  '${b.length == 2 ? '' : 's'}.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            for (var i = 0; i < b.length - 1; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                title: Text(routeDistanceText(b[i + 1] - b[i], u)),
                trailing: i == b.length - 2
                    ? null
                    : IconButton(
                        tooltip: 'Remove split after stage ${i + 1}',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _cuts.removeAt(i)),
                      ),
              ),
          ]),
        ),
      ]),
    );
  }
}
