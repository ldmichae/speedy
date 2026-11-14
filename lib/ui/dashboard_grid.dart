import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dashboard_layout.dart';
import '../core/ride_recording.dart';
import 'dashboard_layout_controller.dart';
import 'dashboard_tiles.dart';
import 'recorder_controller.dart';

const _rowHeight = 100.0;
const _gap = 12.0;
const _sideGap = 16.0;

/// The user's tiles, in two sides that are laid out independently: each is
/// its own three-column grid that fills row by row. Side by side on a wide
/// window, the left above the right on a narrow one.
///
/// In [editing] mode a tile can be dragged anywhere on either side: it takes
/// the slot it is dropped on and any tiles it collides with are pushed on to
/// the next open slots. The arrangement updates live while dragging, so the
/// drop lands as previewed.
class DashboardGrid extends ConsumerStatefulWidget {
  const DashboardGrid({super.key, required this.editing, required this.compact});

  final bool editing;

  /// Narrow window: the two sides stack instead of sitting side by side.
  final bool compact;

  @override
  ConsumerState<DashboardGrid> createState() => _DashboardGridState();
}

class _DashboardGridState extends ConsumerState<DashboardGrid> {
  final _keys = {Side.left: GlobalKey(), Side.right: GlobalKey()};

  /// The tile being dragged, and where it would land: which side, and the
  /// index among that side's other tiles.
  TileKind? _dragging;
  Side? _previewSide;
  int? _previewIndex;

  /// The insertion index for dropping [kind] with its top-left corner at the
  /// global position [corner] on [side], or null if that side is not laid out.
  int? _indexAt(Side side, Offset corner, TileKind kind, double cell,
      DashboardLayout layout) {
    final box = _keys[side]!.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(corner);
    final col = (local.dx / (cell + _gap)).round().clamp(0, sideColumns - 1).toInt();
    final row = (local.dy / (_rowHeight + _gap)).round().clamp(0, 999).toInt();
    final dragged = layout.all.firstWhere((t) => t.kind == kind);
    final others = [for (final t in layout.side(side)) if (t.kind != kind) t];
    return insertionIndexFor(others, dragged, col, row);
  }

  void _endDrag() => setState(() {
        _dragging = null;
        _previewSide = null;
        _previewIndex = null;
      });

  /// [side]'s tiles as they should be drawn now: with the dragged tile moved
  /// to its previewed slot if there is one. Each comes with its position in
  /// the saved layout, which the settings dialog uses.
  List<(int, TileConfig)> _tilesFor(Side side, DashboardLayout layout) {
    final saved = layout.side(side);
    var tiles = [for (final (i, t) in saved.indexed) (i, t)];
    final dragging = _dragging;
    if (widget.editing && dragging != null && _previewSide != null) {
      final dragged = layout.all.firstWhere((t) => t.kind == dragging);
      tiles.removeWhere((e) => e.$2.kind == dragging);
      if (_previewSide == side) {
        tiles.insert(_previewIndex!.clamp(0, tiles.length).toInt(), (-1, dragged));
      }
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(dashboardLayoutProvider);
    final recording = ref.watch(
        recorderProvider.select((r) => r.status != RecStatus.idle));

    Widget side(Side s) => _buildSide(s, layout, recording);
    final left = side(Side.left), right = side(Side.right);

    final sides = widget.compact
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            left,
            if (widget.editing || _hasShown(Side.right, layout, recording))
              const SizedBox(height: _sideGap),
            right,
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: left),
            const SizedBox(width: _sideGap),
            Expanded(child: right),
          ]);

    // A tile dragged over to the other side is rebuilt there, and Flutter
    // only reports the end of a drag to a source that is still mounted, so
    // the end of the gesture is watched here instead.
    void pointerDone(PointerEvent _) {
      if (_dragging != null) _endDrag();
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: pointerDone,
      onPointerCancel: pointerDone,
      child: sides,
    );
  }

  /// Ride-only tiles stay hidden until recording, but are shown while editing
  /// so they can be arranged.
  bool _visible(TileConfig t, bool recording) =>
      widget.editing || recording || !t.kind.rideOnly;

  bool _hasShown(Side s, DashboardLayout layout, bool recording) =>
      layout.side(s).any((t) => _visible(t, recording));

  Widget _buildSide(Side side, DashboardLayout layout, bool recording) {
    final editing = widget.editing;
    final shown = [
      for (final e in _tilesFor(side, layout))
        if (_visible(e.$2, recording)) e
    ];

    return LayoutBuilder(builder: (context, box) {
      final cell = (box.maxWidth - _gap * (sideColumns - 1)) / sideColumns;
      double x(int col) => col * (cell + _gap);
      double y(int row) => row * (_rowHeight + _gap);
      double w(int span) => span * cell + (span - 1) * _gap;
      double h(int rows) => rows * _rowHeight + (rows - 1) * _gap;

      final placements = placeTiles([for (final (_, t) in shown) t]);
      final usedRows = placements.isEmpty
          ? 0
          : placements.map((p) => p.row + p.rows).reduce(math.max);

      final Widget content;
      if (shown.isEmpty) {
        // An empty side still needs somewhere to drop a tile while editing.
        content = SizedBox(
          key: _keys[side],
          height: editing ? 2 * _rowHeight : 0,
          child: editing
              ? const Center(child: Text('Drop tiles here'))
              : const SizedBox.shrink(),
        );
      } else {
        content = SizedBox(
          key: _keys[side],
          // While editing there is an extra row below to drop a tile last.
          height: h(usedRows) + (editing ? _rowHeight + _gap : 0),
          child: Stack(children: [
            for (final (n, p) in placements.indexed)
              AnimatedPositioned(
                key: ValueKey('tile-${shown[n].$2.kind.name}'),
                duration: editing ? const Duration(milliseconds: 180) : Duration.zero,
                curve: Curves.easeOut,
                left: x(p.col),
                top: y(p.row),
                width: w(p.span),
                height: h(p.rows),
                child: editing
                    ? _EditableTile(
                        kind: shown[n].$2.kind,
                        side: side,
                        index: shown[n].$1,
                        size: Size(w(p.span), h(p.rows)),
                        onDragStarted: () =>
                            setState(() => _dragging = shown[n].$2.kind),
                        onDragEnd: _endDrag,
                      )
                    : DashboardTile(kind: shown[n].$2.kind),
              ),
          ]),
        );
      }
      if (!editing) return content;

      final scheme = Theme.of(context).colorScheme;
      return DragTarget<TileKind>(
        onMove: (d) {
          final i = _indexAt(side, d.offset, d.data, cell, layout);
          if (i != null && (i != _previewIndex || _previewSide != side)) {
            setState(() {
              _previewSide = side;
              _previewIndex = i;
            });
          }
        },
        // Dragged off this side: show the saved arrangement unless the tile
        // has already moved on over the other side.
        onLeave: (_) {
          if (_previewSide == side) {
            setState(() {
              _previewSide = null;
              _previewIndex = null;
            });
          }
        },
        onAcceptWithDetails: (d) {
          final i = _indexAt(side, d.offset, d.data, cell, layout) ??
              (_previewSide == side ? _previewIndex : null);
          if (i != null) {
            ref.read(dashboardLayoutProvider.notifier).moveTo(d.data, side, i);
          }
        },
        builder: (_, hovering, __) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering.isNotEmpty ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: content,
        ),
      );
    });
  }
}

/// A tile in edit mode: drag it to a new position; the gear opens its size
/// and content settings.
class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.kind,
    required this.side,
    required this.index,
    required this.size,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  final TileKind kind;
  final Side side;

  /// Position in the saved layout's side, or -1 for a tile that is only
  /// being previewed there.
  final int index;
  final Size size;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Absorbing pointers keeps buttons and the chart inert while arranging.
    final content = AbsorbPointer(child: DashboardTile(kind: kind));

    return Draggable<TileKind>(
      data: kind,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd(),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: DashboardTile(kind: kind),
          ),
        ),
      ),
      // The slot the tile would drop into, while the others flow around it.
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      child: Stack(fit: StackFit.expand, children: [
        content,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outline),
              ),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.drag_indicator, size: 20, color: scheme.outline),
            IconButton(
              key: Key('tile-settings-${kind.name}'),
              tooltip: 'Tile settings',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.settings, size: 20),
              onPressed: index < 0
                  ? null
                  : () => showTileSettings(context, side, index),
            ),
          ]),
        ),
      ]),
    );
  }
}

Future<void> showTileSettings(BuildContext context, Side side, int index) =>
    showDialog<void>(
      context: context,
      builder: (_) => _TileSettings(side: side, index: index),
    );

/// Size, content and removal for one tile. Looks the tile up by its slot, so
/// it follows the tile when its content is swapped.
class _TileSettings extends ConsumerWidget {
  const _TileSettings({required this.side, required this.index});

  final Side side;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dashboardLayoutProvider);
    if (index >= layout.side(side).length) return const SizedBox.shrink();
    final tile = layout.side(side)[index];
    final c = ref.read(dashboardLayoutProvider.notifier);
    final theme = Theme.of(context);

    Widget chips<T>(String title, Iterable<(T, String, bool)> options, T selected,
            void Function(T) onTap) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final (value, label, enabled) in options)
              ChoiceChip(
                label: Text(label),
                selected: value == selected,
                onSelected: enabled ? (_) => onTap(value) : null,
              ),
          ]),
        ]);

    return AlertDialog(
      title: Text(tile.kind.label),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shows', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButton<TileKind>(
              value: tile.kind,
              isExpanded: true,
              items: [
                for (final k in TileKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              // Picking one that is already on the dashboard swaps the two.
              onChanged: (k) => k == null ? null : c.showInstead(tile.kind, k),
            ),
            const SizedBox(height: 16),
            chips<int>(
              'Width',
              [for (final (cols, label) in tileWidths) (cols, label, cols >= tile.kind.minSpan)],
              tile.span,
              (v) => c.resize(tile.kind, span: v),
            ),
            const SizedBox(height: 16),
            chips<int>(
              'Height',
              [
                for (var r = 1; r <= maxTileRows; r++)
                  (r, r == 1 ? '1 row' : '$r rows', r >= tile.kind.minRows)
              ],
              tile.rows,
              (v) => c.resize(tile.kind, rows: v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            c.remove(tile.kind);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
