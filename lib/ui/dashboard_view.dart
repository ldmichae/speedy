import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/units.dart';
import '../core/ride_recording.dart';
import 'layout.dart';
import 'metric_tile.dart';
import 'recorder_controller.dart';
import 'recording_panel.dart';
import 'trainer_controller.dart';
import 'units_controller.dart';

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  @override
  void initState() {
    super.initState();
    // Keep the screen (and browser tab) awake during a ride.
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  String _whole(num? v) => v == null ? '—' : v.round().toString();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(trainerControllerProvider);
    final c = ref.read(trainerControllerProvider.notifier);
    final theme = Theme.of(context);
    final d = s.latest;
    final rideUnits = ref.watch(rideUnitsProvider);
    final active = ref.watch(
        recorderProvider.select((r) => r.status != RecStatus.idle));

    final tiles = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MetricTile(
        label: 'Power (3 s average)',
        value: _whole(s.smoothedPower),
        unit: 'W',
        hero: true,
        footnote: 'Right now ${_whole(d?.powerWatts)} W',
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: MetricTile(
              label: 'Cadence', value: _whole(d?.cadenceRpm), unit: 'rpm'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            label: 'Speed',
            value: d?.speedKph == null
                ? '—'
                : speedIn(d!.speedKph!, rideUnits).toStringAsFixed(1),
            unit: speedUnit(rideUnits),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
              label: 'Heart rate', value: _whole(d?.heartRate), unit: 'bpm'),
        ),
      ]),
    ]);

    final ergCard = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ERG target', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('${s.targetWatts} W', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final delta in const [-25, -10, -5, 5, 10, 25])
                FilledButton.tonal(
                  onPressed: () => c.adjustTarget(delta),
                  child: Text(delta > 0 ? '+$delta' : '$delta'),
                ),
            ]),
          ],
        ),
      ),
    );

    final deviceRow = Row(children: [
      const Icon(Icons.bluetooth_connected, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          s.deviceName ?? 'Trainer',
          style: theme.textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      TextButton.icon(
        onPressed: c.disconnect,
        icon: const Icon(Icons.link_off),
        label: const Text('Disconnect'),
      ),
    ]);

    return LayoutBuilder(builder: (context, box) {
      final wide = isWideLayout(box.maxWidth);

      // Controls, live numbers and (once recording) totals and chart read as
      // one workout: outlined together while a ride is being recorded.
      final Widget workout;
      if (wide) {
        // Live numbers and the ERG target on the left, the ride so far on the
        // right; the chart takes whatever height the window has left.
        final chartHeight = (box.maxHeight - 430).clamp(260.0, 640.0);
        workout = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const WorkoutBar(),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [tiles, const SizedBox(height: 12), ergCard],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: active
                  ? WorkoutSummary(chartHeight: chartHeight)
                  : const _IdleHint(),
            ),
          ]),
        ]);
      } else {
        workout = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const WorkoutBar(),
          const SizedBox(height: 12),
          tiles,
          if (active) ...[
            const SizedBox(height: 12),
            const WorkoutSummary(),
          ],
        ]);
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          deviceRow,
          const SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(active ? 12 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? theme.colorScheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: workout,
          ),
          if (!wide) ...[const SizedBox(height: 12), ergCard],
          if (s.error != null) ...[
            const SizedBox(height: 12),
            Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      );
    });
  }
}

/// Fills the space the ride summary will use, so the wide layout is balanced
/// before recording starts.
class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.show_chart, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('Press Record to start this ride',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Totals and a live chart appear here.',
              style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
