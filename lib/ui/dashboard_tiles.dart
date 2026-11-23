import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dashboard_layout.dart';
import '../core/ride_stats.dart';
import '../core/target_status.dart';
import '../core/units.dart';
import 'format.dart';
import 'layout.dart';
import '../core/plan.dart';
import 'compete_controller.dart';
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
/// theme's own container pair; off target is an amber pair (about 8:1 in
/// either brightness), since the theme has no warning role. Direction is also
/// carried by an arrow and a sign, never by colour alone.
(Color, Color) _warnPair(Brightness b) => b == Brightness.dark
    ? (const Color(0xFF4A3B00), const Color(0xFFFFD866))
    : (const Color(0xFFFFE9A8), const Color(0xFF3D2F00));

/// Background and foreground for a target status.
(Color, Color) _statusColors(ColorScheme s, TargetStatus st) => switch (st) {
      TargetStatus.onTarget => (s.primaryContainer, s.onPrimaryContainer),
      _ => _warnPair(s.brightness),
    };

/// A power reading with the ERG target and how far off it is.
class _PowerTile extends ConsumerWidget {
  const _PowerTile({required this.label, required this.pick});

  final String label;
  final double? Function(TrainerState s) pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final power = ref.watch(trainerControllerProvider.select(pick));
    final target =
        ref.watch(trainerControllerProvider.select((s) => s.targetWatts));
    final simulating =
        ref.watch(trainerControllerProvider.select((s) => s.simulating));
    final theme = Theme.of(context);
    // The whole tile takes the status colour, so it reads from across the
    // room; the delta text and arrow still say it without colour.
    final colors = power == null || simulating
        ? null
        : _statusColors(theme.colorScheme, targetStatus(power, target));
    final fg = colors?.$2;

    return Card(
      margin: EdgeInsets.zero,
      color: colors?.$1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, box) {
          // A tile one row high has no room for a line of its own, so the
          // chip moves up beside the label.
          final roomy = box.maxHeight >= 120;
          final chip = power == null || simulating
              ? null
              : TargetChip(
                  power: power, target: target, large: roomy, bare: true);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium?.copyWith(color: fg),
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
                      Text(_whole(power),
                          style: metricNumberStyle.copyWith(color: fg)),
                      const SizedBox(width: 6),
                      Text('W',
                          style:
                              theme.textTheme.titleMedium?.copyWith(color: fg)),
                    ],
                  ),
                ),
              ),
              if (roomy) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Text('Target $target W',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: fg ?? theme.colorScheme.onSurfaceVariant)),
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
  const TargetChip(
      {required this.power,
      required this.target,
      this.large = false,
      this.bare = false});

  final double power;
  final int target;

  /// Readable from arm's length: used where the tile has room.
  final bool large;

  /// No pill: for a surface that already carries the status colour.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = targetStatus(power, target);
    final delta = targetDelta(power, target);
    final (bg, fg) = _statusColors(scheme, status);

    final (IconData icon, String text, String spoken) = switch (status) {
      TargetStatus.onTarget => (Icons.check, 'On target', 'On target'),
      TargetStatus.above => (
          Icons.arrow_upward,
          '+$delta W',
          '$delta watts above target',
        ),
      TargetStatus.below => (
          Icons.arrow_downward,
          '−${delta.abs()} W',
          '${delta.abs()} watts below target',
        ),
    };

    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: large ? 24 : 16, color: fg),
      SizedBox(width: large ? 6 : 4),
      Text(text,
          style: TextStyle(
            color: fg,
            fontSize: large ? 22 : 14,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
    ]);

    return Semantics(
      label: spoken,
      child: ExcludeSemantics(
        child: bare
            ? content
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: large ? 14 : 10, vertical: large ? 8 : 4),
                  child: content,
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
    final target =
        ref.watch(trainerControllerProvider.select((s) => s.targetWatts));
    final lock = ref.watch(targetLockProvider);
    final following = lock != null;
    final grade =
        ref.watch(trainerControllerProvider.select((s) => s.gradePercent));
    final gear = ref.watch(trainerControllerProvider.select((s) => s.gear));
    final c = ref.read(trainerControllerProvider.notifier);
    final theme = Theme.of(context);

    // On the road the buttons shift gears; under a plan they rest.
    Widget button(int delta) => Tooltip(
          message: switch (lock) {
            TargetLock.plan =>
              'The plan sets the target. Stop the plan to adjust it.',
            TargetLock.simulation =>
              delta > 0 ? 'Shift harder' : 'Shift easier',
            null => delta > 0
                ? 'Raise target by $delta W'
                : 'Lower target by ${-delta} W',
          },
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
                minimumSize: Size.square(isTouchUi(context) ? 56 : 40)),
            icon: Icon(delta > 0 ? Icons.add : Icons.remove),
            onPressed: switch (lock) {
              TargetLock.plan => null,
              TargetLock.simulation => () => c.shift(delta.sign),
              null => () => c.adjustTarget(delta),
            },
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          button(-_step),
          Expanded(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (lock == TargetLock.plan)
                Text('Target set by plan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium)
              else
                const _ModeSwitch(),
              Flexible(
                child: FittedBox(
                  child: Text(
                      grade != null
                          ? '${grade.toStringAsFixed(1)}%'
                          : '$target W',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
              ),
              if (grade != null)
                Tooltip(
                  message: 'Virtual gear: arrow up/down, or Zwift shifters '
                      '(connect them where you connect the trainer).',
                  child: SizedBox(
                      height: 32,
                      child: Row(children: [
                        Text('Gear $gear', style: theme.textTheme.labelLarge),
                        const SizedBox(width: 8),
                        Expanded(child: GearBar(gear: gear)),
                      ])),
                )
              else
                Tooltip(
                  message: 'Change the step size',
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: following
                        ? null
                        : () => setState(() => _step = _steps[
                            (_steps.indexOf(_step) + 1) % _steps.length]),
                    child: Text('±$_step W'),
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

/// Where [gear] sits among the virtual gears: one notch per gear, lit up to
/// the one you are in, the neutral gear's notch taller, so the range reads
/// at a glance mid-effort.
class GearBar extends StatelessWidget {
  const GearBar({super.key, required this.gear, this.height = 12});

  final int gear;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Gear $gear of ${TrainerState.gearCount}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
            painter:
                _GearBarPainter(gear, scheme.primary, scheme.outlineVariant)),
      ),
    );
  }
}

class _GearBarPainter extends CustomPainter {
  _GearBarPainter(this.gear, this.on, this.off);
  final int gear;
  final Color on, off;

  @override
  void paint(Canvas canvas, Size size) {
    const n = TrainerState.gearCount, gap = 2.0;
    final w = (size.width - gap * (n - 1)) / n;
    if (w <= 0) return;
    for (var i = 1; i <= n; i++) {
      // Notches grow towards the hard end; the neutral one stands out.
      final h = i == TrainerState.neutralGear
          ? size.height
          : size.height * (0.45 + 0.4 * i / n);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH((i - 1) * (w + gap), size.height - h, w, h),
              Radius.circular(w / 3)),
          Paint()..color = i <= gear ? on : off);
    }
  }

  @override
  bool shouldRepaint(_GearBarPainter old) =>
      old.gear != gear || old.on != on || old.off != off;
}

/// ERG or Road: whether the trainer holds the target power, or simulates a
/// road (the route's climbs, or flat with no route) that you ride on gears.
class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final road = ref.watch(rideSessionProvider.select((s) => s.road));
    final route = ref.watch(routeRunProvider)?.course;
    final racing = ref.watch(competeProvider.select((r) => r != null));
    final canRoad = route == null || canSimulate(route);
    return Tooltip(
      message: racing
          ? 'A race is ridden on the road.'
          : !canRoad
              ? 'This route has no elevation yet, so it rides in ERG.'
              : 'ERG: the trainer holds your target power.\n'
                  'Road: it simulates ${route == null ? 'a flat road' : 'the '
                      'route\'s climbs'}; shift with the arrow keys or Zwift '
                  'shifters.',
      // No taller than the label it replaced, shrinking on a small tile.
      child: SizedBox(
        height: 24,
        child: FittedBox(
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              const ButtonSegment(value: false, label: Text('ERG')),
              ButtonSegment(
                  value: true, label: const Text('Road'), enabled: canRoad),
            ],
            selected: {road},
            onSelectionChanged: racing
                ? null
                : (s) =>
                    ref.read(rideSessionProvider.notifier).setRoad(s.first),
          ),
        ),
      ),
    );
  }
}
