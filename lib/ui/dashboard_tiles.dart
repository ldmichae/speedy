import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dashboard_layout.dart';
import '../core/ride_stats.dart';
import '../core/target_status.dart';
import '../core/units.dart';
import 'format.dart';
import '../core/plan.dart';
import 'metric_tile.dart';
import 'route_tile.dart';
import 'recorder_controller.dart';
import 'ride_chart.dart';
import 'rider_profile_controller.dart';
import 'trainer_controller.dart';
import 'units_controller.dart';
import 'ride_session.dart';

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
        return _PowerTile(label: kind.label, pick: (s) => s.smoothedPower);
      case TileKind.powerNow:
        return _PowerTile(
            label: kind.label, pick: (s) => s.latest?.powerWatts?.toDouble());
      case TileKind.cadence:
        return MetricTile(
            label: kind.label,
            value: _whole(trainer((s) => s.latest?.cadenceRpm)),
            unit: 'rpm');
      case TileKind.heartRate:
        final bpm = trainer((s) => s.latest?.heartRate);
        return MetricTile(
          label: kind.label,
          value: _whole(bpm),
          unit: 'bpm',
          // A trainer without a heart-rate strap sends none: say so, rather
          // than leave a dash that looks like a fault.
          note: bpm == null ? 'No sensor' : null,
        );
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
        final hasProfile =
            ref.watch(riderProfileProvider.select((p) => p.complete));
        return MetricTile(
          label: kind.label,
          value: _whole(stats((s) => s.kcal)),
          unit: 'kcal',
          // Energy needs the rider profile; point at where to set it up.
          note: hasProfile ? null : 'Add profile',
        );
      case TileKind.ergTarget:
        return const _ErgTile();
      case TileKind.chart:
        return const _ChartTile();
      case TileKind.route:
        return const RouteMapTile();
    }
  }
}

/// Status colours for "how am I doing against the target". On target uses the
/// theme's own container pair; off target is a dark amber pair (about 8:1),
/// since the theme has no warning role. Direction is also carried by an
/// arrow and a sign, never by colour alone.
const _warnContainer = Color(0xFF4A3B00);
const _onWarnContainer = Color(0xFFFFD866);

/// A power reading with the ERG target and how far off it is.
class _PowerTile extends ConsumerWidget {
  const _PowerTile({required this.label, required this.pick});

  final String label;
  final double? Function(TrainerState s) pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final power = ref.watch(trainerControllerProvider.select(pick));
    final target = ref.watch(trainerControllerProvider.select((s) => s.targetWatts));
    final simulating = ref.watch(trainerControllerProvider.select((s) => s.simulating));
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, box) {
          // A tile one row high has no room for a line of its own, so the
          // chip moves up beside the label.
          final roomy = box.maxHeight >= 120;
          final chip = power == null || simulating
              ? null
              : TargetChip(power: power, target: target);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (!roomy && chip != null) ...[const Spacer(), chip],
              ]),
              const SizedBox(height: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _whole(power),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('W', style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
              if (roomy) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Text('Target $target W',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  if (chip != null) chip,
                ]),
              ],
            ],
          );
        }),
      ),
    );
  }
}

/// How measured power compares with the ERG target: a pill with an icon, a
/// signed delta and a colour, so no state relies on colour alone.
class TargetChip extends StatelessWidget {
  const TargetChip({required this.power, required this.target});

  final double power;
  final int target;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = targetStatus(power, target);
    final delta = targetDelta(power, target);

    final (Color bg, Color fg, IconData icon, String text, String spoken) =
        switch (status) {
      TargetStatus.onTarget => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check,
          'On target',
          'On target',
        ),
      TargetStatus.above => (
          _warnContainer,
          _onWarnContainer,
          Icons.arrow_upward,
          '+$delta W',
          '$delta watts above target',
        ),
      TargetStatus.below => (
          _warnContainer,
          _onWarnContainer,
          Icons.arrow_downward,
          '−${delta.abs()} W',
          '${delta.abs()} watts below target',
        ),
    };

    return Semantics(
      label: spoken,
      child: ExcludeSemantics(
        child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ]),
        ),
      ),
      ),
    );
  }
}

/// The ERG controls: a stepper around the target, − and + by the chosen step
/// (5, 10 or 25 W; the arrow keys do 5 and Shift 25). One row high.
class _ErgTile extends ConsumerStatefulWidget {
  const _ErgTile();

  @override
  ConsumerState<_ErgTile> createState() => _ErgTileState();
}

class _ErgTileState extends ConsumerState<_ErgTile> {
  static const _steps = [5, 10, 25];
  int _step = 5;

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(trainerControllerProvider.select((s) => s.targetWatts));
    final lock = ref.watch(targetLockProvider);
    final following = lock != null;
    final grade = ref.watch(trainerControllerProvider.select((s) => s.gradePercent));
    final c = ref.read(trainerControllerProvider.notifier);
    final theme = Theme.of(context);

    final why = switch (lock) {
      TargetLock.plan => 'The plan sets the target. Stop the plan to adjust it.',
      TargetLock.simulation =>
        'The route sets the resistance. Stop the route to adjust it.',
      null => null,
    };
    Widget button(int delta) => Tooltip(
          message: why ??
              (delta > 0 ? 'Raise target by $delta W' : 'Lower target by ${-delta} W'),
          child: IconButton.filledTonal(
            icon: Icon(delta > 0 ? Icons.add : Icons.remove),
            onPressed: following ? null : () => c.adjustTarget(delta),
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          button(-_step),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Tooltip(
                message: 'ERG mode: the trainer holds this power whatever your '
                    'cadence.\nArrow up/down: ±5 W. Shift + arrow: ±25 W.',
                child: Text(
                    switch (lock) {
                      TargetLock.plan => 'ERG target · plan',
                      TargetLock.simulation => 'Simulation · grade',
                      null => 'ERG target',
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium),
              ),
              Flexible(
                child: FittedBox(
                  child: Text(
                      grade != null ? '${grade.toStringAsFixed(1)}%' : '$target W',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
              ),
              Tooltip(
                message: 'Change the step size',
                child: InkWell(
                  onTap: following
                      ? null
                      : () => setState(() =>
                          _step = _steps[(_steps.indexOf(_step) + 1) % _steps.length]),
                  child: Text('±$_step W',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            ]),
          ),
          button(_step),
        ]),
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
    final run = ref.watch(planRunProvider);
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
                planned: run?.steps.outline(run.origin.toDouble()),
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
