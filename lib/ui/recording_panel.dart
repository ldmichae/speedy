import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_recording.dart';
import '../core/ride_stats.dart';
import 'format.dart';
import 'recorder_controller.dart';
import 'ride_chart.dart';
import 'rider_profile_controller.dart';
import 'units_controller.dart';

class RecordingPanel extends ConsumerWidget {
  const RecordingPanel({super.key});

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final c = ref.read(recorderProvider.notifier);
    final rec = ref.read(recorderProvider);
    final wasRecording = rec.status == RecStatus.recording;
    c.pause();

    if (rec.samples.isEmpty) {
      c.discard();
      return;
    }

    final stats = RideStats.of(rec.samples,
        kcal: rideKcal(rec.samples, ref.read(riderProfileProvider)));

    final choice = await showDialog<_StopChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End ride?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RideStatRow(stats: stats),
            const SizedBox(height: 12),
            Text('Saves to history and exports as '
                '${ref.read(rideFormatProvider).label} (change in Preferences).'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, _StopChoice.keepGoing),
              child: const Text('Keep riding')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _StopChoice.discard),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _StopChoice.save),
              child: const Text('Save')),
        ],
      ),
    );
    if (!context.mounted) return;

    switch (choice) {
      case _StopChoice.save:
        final messenger = ScaffoldMessenger.of(context);
        try {
          final path = await c.save();
          messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
        } catch (e) {
          // Recording is intact; the user can retry or discard.
          messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
        }
      case _StopChoice.discard:
        c.discard();
      case _StopChoice.keepGoing || null:
        if (wasRecording) c.resume();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(recorderProvider);
    final settings = ref.watch(chartSettingsProvider);
    final profile = ref.watch(riderProfileProvider);
    final c = ref.read(recorderProvider.notifier);
    final theme = Theme.of(context);
    final kcal = rideKcal(rec.samples, profile);

    final controls = switch (rec.status) {
      RecStatus.idle => [
          FilledButton.icon(
            onPressed: c.start,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Record'),
          ),
        ],
      RecStatus.recording => [
          FilledButton.tonalIcon(
            onPressed: c.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
          OutlinedButton.icon(
            onPressed: () => _stop(context, ref),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ],
      RecStatus.paused => [
          FilledButton.icon(
            onPressed: c.resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
          OutlinedButton.icon(
            onPressed: () => _stop(context, ref),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ],
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (rec.status == RecStatus.recording)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.circle, size: 12, color: theme.colorScheme.error),
                ),
              Text(
                rec.status == RecStatus.idle
                    ? 'Ride recording'
                    : rec.status == RecStatus.paused
                        ? 'Paused  ${clock(rec.elapsed)}'
                        : clock(rec.elapsed),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              Wrap(spacing: 8, children: controls),
            ]),
            if (rec.status != RecStatus.idle) ...[
              const SizedBox(height: 4),
              Text(
                kcal != null
                    ? '≈ ${kcal.round()} kcal burned'
                    : 'Add your rider profile in Preferences to estimate calories',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: RideChart(
                samples: rec.samples,
                settings: settings,
                units: ref.watch(rideUnitsProvider),
              ),
            ),
            const SizedBox(height: 12),
            ChartOptions(settings: settings),
          ],
        ),
      ),
    );
  }
}

enum _StopChoice { save, discard, keepGoing }
