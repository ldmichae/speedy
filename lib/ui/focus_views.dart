import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/dashboard_layout.dart';
import 'dashboard_tiles.dart';
import 'route_tile.dart';

/// Tiles the focus views show themselves, so the metrics grid below skips them.
const focusTiles = {TileKind.chart, TileKind.route};

double _heroHeight(double width) => (width * 0.5).clamp(320.0, 560.0);

/// Full-width map with the elevation profile laid over its bottom edge.
class MapFocus extends StatelessWidget {
  const MapFocus({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, box) => SizedBox(
          height: _heroHeight(box.maxWidth),
          child: const RouteMapTile(elevation: MapElevation.overlay),
        ),
      );
}

/// Full-width chart with the map in a corner pane. Drag the pane's inner
/// corner handle to resize it.
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
        final h = _heroHeight(box.maxWidth);
        final maxW = math.max(_min.width, box.maxWidth * 0.7);
        final maxH = math.max(_min.height, h - 2 * _inset);
        final w = _pane.width.clamp(_min.width, maxW).toDouble();
        final ph = _pane.height.clamp(_min.height, maxH).toDouble();
        return SizedBox(
          height: h,
          child: Stack(children: [
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
          ]),
        );
      });
}
