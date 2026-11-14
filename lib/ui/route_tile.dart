import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/route.dart';
import 'route_controller.dart';
import 'route_map.dart';
import 'route_screen.dart';

/// Dashboard tile: the route being ridden and the blue dot on it.
class RouteMapTile extends ConsumerStatefulWidget {
  const RouteMapTile({super.key});

  @override
  ConsumerState<RouteMapTile> createState() => _RouteMapTileState();
}

class _RouteMapTileState extends ConsumerState<RouteMapTile> {
  final _map = MapController();
  bool _ready = false;
  bool _follow = true;

  static const _followZoom = 15.0;

  void _fit(SavedRoute r) {
    if (!_ready) return;
    _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(r.path), padding: const EdgeInsets.all(32)));
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(routeProgressProvider);
    ref.listen(routeProgressProvider, (_, p) {
      if (p == null || !_ready) return;
      _follow ? _map.move(p.position, _followZoom) : null;
    });

    if (progress == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('No route selected'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RoutesScreen()),
              ),
              child: const Text('Choose a route'),
            ),
          ]),
        ),
      );
    }

    final r = progress.route;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: progress.position,
            initialZoom: _followZoom,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: () {
              _ready = true;
              _follow ? _map.move(progress.position, _followZoom) : _fit(r);
            },
          ),
          children: [
            ...mapBaseLayers(ref),
            PolylineLayer(polylines: [routeLine(r.path)]),
            MarkerLayer(markers: [riderMarker(progress.position)]),
          ],
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Row(children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(progress.finished
                    ? '${r.name} · finished'
                    : '${r.name} · ${routeDistanceText(r.lengthMeters - progress.meters)} to go'),
              ),
            ),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: _follow ? 'Show whole route' : 'Follow me',
              icon: Icon(_follow ? Icons.zoom_out_map : Icons.my_location),
              onPressed: () {
                setState(() => _follow = !_follow);
                _follow ? _map.move(progress.position, _followZoom) : _fit(r);
              },
            ),
            IconButton.filledTonal(
              tooltip: 'Stop route',
              icon: const Icon(Icons.close),
              onPressed: ref.read(routeRunProvider.notifier).stop,
            ),
          ]),
        ),
      ]),
    );
  }
}
