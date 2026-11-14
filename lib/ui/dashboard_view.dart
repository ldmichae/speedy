import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/units.dart';
import 'metric_tile.dart';
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
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
        ]),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Card(
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
        ),
        const SizedBox(height: 12),
        const RecordingPanel(),
        if (s.error != null) ...[
          const SizedBox(height: 12),
          Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
