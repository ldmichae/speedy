import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/route.dart';
import '../core/units.dart';
import 'elevation_chart.dart';
import 'route_controller.dart';
import 'route_map.dart';
import 'units_controller.dart';
import 'navigation.dart';

enum MapElevation { below, overlay, none }

/// Dashboard tile: the route being ridden and the blue dot on it.
class RouteMapTile extends ConsumerStatefulWidget {
  const RouteMapTile({super.key, this.elevation = MapElevation.below});

  /// Where the elevation profile goes: under the map, over its bottom edge, or
  /// not at all.
  final MapElevation elevation;

  static String label(RouteProgress p, UnitSystem u) {
    final c = p.course;
    if (p.finished) return '${c.name} · finished';
    final g = c.gradeAt(p.meters);
    final grade = g == null ? '' : ' · ${g.toStringAsFixed(1)}%';
    if (c.stageCount == 1) {
      return '${c.name} · ${routeDistanceText(c.lengthMeters - p.meters, u)} to go$grade';
    }
    final loading =
        c.stage(p.stage).elevation == null ? ' · no elevation yet' : '';
    return 'Stage ${p.stage + 1}/${c.stageCount} · '
        '${routeDistanceText(p.stageRemaining, u)} to go · '
        '${routeDistanceText(c.lengthMeters - p.meters, u)} left$grade$loading';
  }

  @override
  ConsumerState<RouteMapTile> createState() => _RouteMapTileState();
}

class _RouteMapTileState extends ConsumerState<RouteMapTile> {
  final _map = MapController();
  bool _ready = false;
  bool _follow = true;

  static const _followZoom = 15.0;
  static const _overlayHeight = 64.0;

  void _fit(SavedRoute r) {
    if (!_ready) return;
    _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(r.path),
        padding: const EdgeInsets.all(32)));
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
              onPressed: () =>                  ref.read(pageProvider.notifier).state = AppPage.routes,
              child: const Text('Choose a route'),
            ),
          ]),
        ),
      );
    }

    final r = progress.course.stage(progress.stage); // the stage being ridden
    final profile = r.elevation == null || widget.elevation == MapElevation.none
        ? null
        : ElevationChart(
            profile: r.elevation!,
            height: _overlayHeight,
            riderMeters: progress.stageMeters);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: progress.position,
                initialZoom: _followZoom,
                minZoom: minMapZoom,
                maxZoom: maxMapZoom,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
                onMapReady: () {
                  _ready = true;
                  _follow ? _map.move(progress.position, _followZoom) : _fit(r);
                },
              ),
              children: [
                ...mapBaseLayers(ref,
                    panBuffer: 0,
                    bottomInset: profile != null &&
                            widget.elevation == MapElevation.overlay
                        ? _overlayHeight
                        : 0),
                PolylineLayer(polylines: [routeLine(r.path)]),
                MarkerLayer(markers: [riderMarker(progress.position)]),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(children: [
                Flexible(
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
                    child: Text(RouteMapTile.label(progress, ref.watch(rideUnitsProvider)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                )),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: _follow ? 'Show whole route' : 'Follow me',
                  icon: Icon(_follow ? Icons.zoom_out_map : Icons.my_location),
                  onPressed: () {
                    setState(() => _follow = !_follow);
                    _follow
                        ? _map.move(progress.position, _followZoom)
                        : _fit(r);
                  },
                ),
                IconButton.filledTonal(
                  tooltip: 'Stop route',
                  icon: const Icon(Icons.close),
                  onPressed: ref.read(routeRunProvider.notifier).stop,
                ),
              ]),
            ),
            // Flush with the map's bottom and side edges; the credits are
            // lifted above it (see mapBaseLayers' bottomInset).
            if (profile != null && widget.elevation == MapElevation.overlay)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.85),
                  child: profile,
                ),
              ),
          ]),
        ),
        if (profile != null && widget.elevation == MapElevation.below)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: profile,
          ),
      ]),
    );
  }
}
