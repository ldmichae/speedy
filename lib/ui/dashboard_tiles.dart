import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dashboard_layout.dart';
import '../core/ride_stats.dart';
import '../core/units.dart';
import 'format.dart';
import 'metric_tile.dart';
import 'recorder_controller.dart';
import 'ride_chart.dart';
import 'trainer_controller.dart';
import 'units_controller.dart';

String _whole(num? v) => v == null ? '—' : v.round().toString();

/// The content for one dashboard tile. Fills the space it is given.
class DashboardTile extends ConsumerWidget {
  const DashboardTile({super.key, required this.kind});

  final TileKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Each tile watches only the value it shows, so a new reading rebuilds
    // just the tiles that changed.
    T trainer<T>(T Function(TrainerState s) pick) =>
        ref.watch(trainerControllerProvider.select(pick));
    T stats<T>(T Function(RideStats s) pick) =>
        ref.watch(liveRideStatsProvider.select(pick));

    switch (kind) {
      case TileKind.powerAvg:
        return MetricTile(
            label: kind.label,
            value: _whole(trainer((s) => s.smoothedPower)),
            unit: 'W');
      case TileKind.powerNow:
        return MetricTile(
            label: kind.label,
            value: _whole(trainer((s) => s.latest?.powerWatts)),
            unit: 'W');
      case TileKind.cadence:
        return MetricTile(
            label: kind.label,
            value: _whole(trainer((s) => s.latest?.cadenceRpm)),
            unit: 'rpm');
      case TileKind.heartRate:
        return MetricTile(
            label: kind.label,
            value: _whole(trainer((s) => s.latest?.heartRate)),
            unit: 'bpm');
      case TileKind.speed:
        final units = ref.watch(rideUnitsProvider);
        final kph = trainer((s) => s.latest?.speedKph);
        return MetricTile(
          label: kind.label,
          value: kph == null ? '—' : speedIn(kph, units).toStringAsFixed(1),
          unit: speedUnit(units),
        );
      case TileKind.time:
        return MetricTile(
          label: kind.label,
          value: clock(ref.watch(recorderProvider.select((r) => r.elapsed))),
          unit: '',
        );
      case TileKind.distance:
        final units = ref.watch(rideUnitsProvider);
        final meters = stats((s) => s.distanceMeters);
        return MetricTile(
          label: kind.label,
          value: distanceIn(meters / 1000, units).toStringAsFixed(2),
          unit: distanceUnit(units),
        );
      case TileKind.avgPower:
        return MetricTile(
            label: kind.label,
            value: _whole(stats((s) => s.avgPower)),
            unit: 'W');
      case TileKind.energy:
        return MetricTile(
            label: kind.label,
            value: _whole(stats((s) => s.kcal)),
            unit: 'kcal');
      case TileKind.ergTarget:
        return const _ErgTile();
      case TileKind.chart:
        return const _ChartTile();
    }
  }
}

class _ErgTile extends ConsumerWidget {
  const _ErgTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(trainerControllerProvider.select((s) => s.targetWatts));
    final c = ref.read(trainerControllerProvider.notifier);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ERG target', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: Text('$target W',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            // Shrinks to fit rather than overflowing a narrow tile.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [
                for (final delta in const [-25, -10, -5, 5, 10, 25])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.tonal(
                      onPressed: () => c.adjustTarget(delta),
                      child: Text(delta > 0 ? '+$delta' : '$delta'),
                    ),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartTile extends ConsumerWidget {
  const _ChartTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(recorderProvider);
    final settings = ref.watch(chartSettingsProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RideChart(
                samples: rec.samples,
                settings: settings,
                units: ref.watch(rideUnitsProvider),
              ),
            ),
            const SizedBox(height: 8),
            ChartOptions(settings: settings),
          ],
        ),
      ),
    );
  }
}
