import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/dashboard_layout.dart';
import 'dashboard_tiles.dart';
import 'route_tile.dart';

/// Full-width map with the elevation profile laid over its bottom edge.
/// Fills the space it is given.
class MapFocus extends StatelessWidget {
  const MapFocus({super.key});

  @override
  Widget build(BuildContext context) =>
      const RouteMapTile(elevation: MapElevation.overlay);
}

/// The fixed metrics under the map/chart: power and the ERG controls, then
/// cadence, speed, heart rate and distance. Not editable; a narrow window
/// puts the small four on a second row.
class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.compact});

  final bool compact;

  static const rowHeight = 100.0, gap = 12.0;

  /// Total height for the given layout.
  static double heightFor(bool compact) =>
      compact ? 2 * rowHeight + gap : rowHeight;

  @override
  Widget build(BuildContext context) {
    Widget row(List<(TileKind, int)> tiles) => SizedBox(
          height: rowHeight,
          child: Row(children: [
            for (final (i, (k, flex)) in tiles.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(flex: flex, child: DashboardTile(kind: k)),
            ],
          ]),
        );
    const big = [(TileKind.powerAvg, 3), (TileKind.ergTarget, 2)];
    const small = [
      (TileKind.cadence, 1),
      (TileKind.speed, 1),
      (TileKind.heartRate, 1),
      (TileKind.distance, 1),
    ];
    return compact
        ? Column(children: [row(big), const SizedBox(height: gap), row(small)])
        : row([...big, ...small]);
  }
}

/// Full-width chart with the map in a corner pane. Drag the pane's inner
/// corner handle to resize it. Fills the space it is given.
class ChartFocus extends StatefulWidget {
  const ChartFocus({super.key});

  @override
  State<ChartFocus> createState() => _ChartFocusState();
}

class _ChartFocusState extends State<ChartFocus> {
  // shortcut: pane size resets each visit, persist it if riders ask.
  Size _pane = const Size(260, 190);

  static const _min = Size(160, 120), _inset = 8.0, _handle = 28.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        final maxW = math.max(_min.width, box.maxWidth * 0.7);
        final maxH = math.max(_min.height, box.maxHeight - 2 * _inset);
        final w = _pane.width.clamp(_min.width, maxW).toDouble();
        final ph = _pane.height.clamp(_min.height, maxH).toDouble();
        return Stack(children: [
          const Positioned.fill(child: DashboardTile(kind: TileKind.chart)),
          Positioned(
            top: _inset,
            right: _inset,
            width: w,
            height: ph,
            child: Stack(children: [
              const Positioned.fill(
                  child: RouteMapTile(elevation: MapElevation.none)),
              // Bottom-left is the corner facing the chart's middle, so the
              // pane grows leftwards and downwards from its fixed corner.
              Positioned(
                left: 0,
                bottom: 0,
                width: _handle,
                height: _handle,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownLeft,
                  child: GestureDetector(
                    key: const Key('paneResize'),
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() => _pane = Size(
                        (w - d.delta.dx).clamp(_min.width, maxW).toDouble(),
                        (ph + d.delta.dy).clamp(_min.height, maxH).toDouble())),
                    child: const Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.open_in_full, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]);
      });
}
