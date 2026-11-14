import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/route.dart';
import '../core/tour.dart';
import '../devices/trainer.dart';
import 'elevation_chart.dart';
import 'route_controller.dart';
import 'route_map.dart';
import 'route_screen.dart';
import 'tour_controller.dart';
import 'navigation.dart';
import 'trainer_controller.dart';

class ToursScreen extends ConsumerWidget {
  const ToursScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('New tour'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: const Text('Next')),
          ],
        );
      },
    );
    if (name == null || !context.mounted) return;
    final stage =
        await Navigator.of(context).push<SavedRoute>(MaterialPageRoute(
      builder: (_) => const RouteEditor(
          title: 'Stage 1',
          initialName: 'Stage 1',
          fetchElevationOnSave: false),
    ));
    if (stage == null) return;
    final tour = Tour(DateTime.now().millisecondsSinceEpoch.toString(),
        name.trim().isEmpty ? 'Untitled tour' : name.trim(), [stage]);
    await ref.read(toursProvider.notifier).upsert(tour);
    if (context.mounted) {
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TourScreen(tourId: tour.id)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tours = ref.watch(toursProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New tour'),
      ),
      body: tours.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load tours: $e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No tours yet. A tour is a long ride planned as '
                      'stages, with elevation loaded only when you need it.'),
                ),
              )
            : ListView(padding: const EdgeInsets.only(top: 8, bottom: 88), children: [
                for (final t in list)
                  ListTile(
                    leading: const Icon(Icons.hiking),
                    title: Text(t.name),
                    subtitle: Text('${t.stageCount} stages · '
                        '${routeDistanceText(t.lengthMeters)} · '
                        '${t.completed.length} done'),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => TourScreen(tourId: t.id))),
                  ),
              ]),
      ),
    );
  }
}

/// One tour: the whole thing on a map and a profile, then its stages.
class TourScreen extends ConsumerWidget {
  const TourScreen({super.key, required this.tourId});
  final String tourId;

  Future<void> _addStage(BuildContext context, WidgetRef ref, Tour tour) async {
    final n = tour.stageCount + 1;
    final stage =
        await Navigator.of(context).push<SavedRoute>(MaterialPageRoute(
      builder: (_) => RouteEditor(
        title: 'Stage $n',
        initialName: 'Stage $n',
        startAt: tour.stages.last.path.last,
        fetchElevationOnSave: false,
      ),
    ));
    if (stage == null) return;
    await ref.read(toursProvider.notifier).upsert(tour.withAddedStage(stage));
  }

  void _ride(
      BuildContext context, WidgetRef ref, Tour tour, int stage, bool sim) {
    ref
        .read(routeRunProvider.notifier)
        .start(tour, simulate: sim, stage: stage);
    Navigator.of(context).popUntil((r) => r.isFirst);
    ref.read(pageProvider.notifier).state = AppPage.ride;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(toursProvider.select(
        (a) => a.valueOrNull?.where((t) => t.id == tourId).firstOrNull));
    if (tour == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('Tour not found')));
    }
    final loads = ref.watch(tourElevationProvider);
    final connected = ref.watch(trainerControllerProvider
        .select((s) => s.status == TrainerStatus.connected));
    final anyLoading = loads.values.any((l) => l.loading);
    final loaded = tour.stages.where((s) => s.elevation != null);
    final climb = loaded.fold(0.0, (a, s) => a + s.elevation!.climb);
    final loader = ref.read(tourElevationProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(tour.name),
        actions: [
          IconButton(
            tooltip: 'Delete tour',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this tour?'),
                  content:
                      Text('${tour.name} and its ${tour.stageCount} stages '
                          'will be removed.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(toursProvider.notifier).delete(tour.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStage(context, ref, tour),
        icon: const Icon(Icons.add),
        label: const Text('Add stage'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
        SizedBox(height: 220, child: _Overview(tour: tour)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            '${routeDistanceText(tour.lengthMeters)} · ${tour.stageCount} stages · '
            '${loaded.length}/${tour.stageCount} with elevation'
            '${loaded.isEmpty ? '' : ' · ↑ ${climb.round()} m so far'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _TourProfile(tour: tour),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: anyLoading || loaded.length == tour.stageCount
                  ? null
                  : () => loader.loadAll(tour.id),
              icon: const Icon(Icons.terrain),
              label: Text(anyLoading
                  ? 'Loading elevation…'
                  : 'Load elevation for all stages'),
            ),
          ),
        ),
        const Divider(),
        for (final (i, s) in tour.stages.indexed)
          _StageTile(
            tour: tour,
            index: i,
            stage: s,
            load: loads[stageKey(tour.id, i)],
            connected: connected,
            onLoad: () => loader.load(tour.id, i),
            onRide: (sim) => _ride(context, ref, tour, i, sim),
            onDelete: tour.stageCount == 1
                ? null
                : () => ref
                    .read(toursProvider.notifier)
                    .upsert(tour.withoutStage(i)),
          ),
      ]),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.tour,
    required this.index,
    required this.stage,
    required this.load,
    required this.connected,
    required this.onLoad,
    required this.onRide,
    required this.onDelete,
  });

  final Tour tour;
  final int index;
  final SavedRoute stage;
  final StageLoad? load;
  final bool connected;
  final VoidCallback onLoad;
  final void Function(bool simulate) onRide;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final done = tour.completed.contains(index);
    final ele = stage.elevation;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        child: done ? const Icon(Icons.check) : Text('${index + 1}'),
      ),
      title: Text(stage.name),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(routeDistanceText(stage.lengthMeters) +
            (ele == null
                ? ''
                : ' · ↑ ${ele.climb.round()} m ↓ ${ele.descent.round()} m')),
        if (load?.loading ?? false)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: SizedBox(width: 120, child: LinearProgressIndicator()),
          ),
        if (load?.message != null)
          Text(load!.message!, style: TextStyle(color: scheme.error)),
      ]),
      isThreeLine: load != null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ele == null)
          TextButton(
            onPressed: (load?.loading ?? false) ? null : onLoad,
            child: Text(load?.message != null ? 'Retry' : 'Load elevation'),
          ),
        IconButton(
          tooltip: connected
              ? 'Ride from this stage in ERG (starts recording)'
              : 'Connect a trainer to ride',
          icon: const Icon(Icons.play_arrow),
          onPressed: connected ? () => onRide(false) : null,
        ),
        IconButton(
          tooltip: connected
              ? 'Ride from this stage with simulated climbs'
              : 'Connect a trainer to ride',
          icon: const Icon(Icons.terrain),
          onPressed: connected ? () => onRide(true) : null,
        ),
        if (onDelete != null)
          IconButton(
            tooltip: 'Delete stage',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
      ]),
    );
  }
}

/// All stages on one map, alternating colours so the joins are visible.
class _Overview extends ConsumerWidget {
  const _Overview({required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = [for (final s in tour.stages) ...s.path];
    return FlutterMap(
      // A new key when stages change, so the camera refits.
      key: ValueKey('${tour.id}/${tour.stageCount}'),
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(all),
            padding: const EdgeInsets.all(24)),
        minZoom: minMapZoom,
        maxZoom: maxMapZoom,
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        ...mapBaseLayers(ref, panBuffer: 0),
        PolylineLayer(polylines: [
          for (final (i, s) in tour.stages.indexed)
            Polyline(
              points: s.path,
              strokeWidth: 4,
              color:
                  i.isEven ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
            ),
        ]),
      ],
    );
  }
}

/// One shared-scale profile across the tour; stages without elevation show
/// as an empty slot of the right width.
class _TourProfile extends StatelessWidget {
  const _TourProfile({required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final loaded = [
      for (final s in tour.stages)
        if (s.elevation != null) s.elevation!
    ];
    if (loaded.isEmpty) {
      return Text('No elevation loaded yet.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final lo =
        loaded.map((e) => e.minElevation).reduce((a, b) => a < b ? a : b);
    final hi =
        loaded.map((e) => e.maxElevation).reduce((a, b) => a > b ? a : b);
    return Row(children: [
      for (final s in tour.stages)
        Expanded(
          flex: s.lengthMeters.round().clamp(1, 1 << 30),
          child: s.elevation == null
              ? Container(
                  height: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                )
              : ElevationChart(
                  profile: s.elevation!, height: 64, yMin: lo, yMax: hi),
        ),
    ]);
  }
}
