import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_recording.dart';
import '../core/ride_stats.dart';
import 'format.dart';
import '../core/power_fun.dart';
import 'power_fun.dart';
import 'recorder_controller.dart';
import 'rider_profile_controller.dart';

/// Timer and record/pause/stop controls. Always visible, so starting a ride
/// does not move anything on screen.
class WorkoutBar extends ConsumerWidget {
  const WorkoutBar({super.key, this.trailing});

  /// Shown at the end of the row, after the controls.
  final Widget? trailing;

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
            PowerFun(joules: rideJoules(rec.samples), title: 'This ride'),
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
    final c = ref.read(recorderProvider.notifier);
    final theme = Theme.of(context);

    // 48 px high: the controls you reach for mid-ride. Space does the same as
    // Record, Pause and Resume.
    const size = Size(0, 48);
    final fill = FilledButton.styleFrom(minimumSize: size);
    final outline = OutlinedButton.styleFrom(minimumSize: size);

    Widget stop() => Tooltip(
          message: 'Stop and save or discard',
          child: OutlinedButton.icon(
            style: outline,
            onPressed: () => _stop(context, ref),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        );

    final controls = switch (rec.status) {
      RecStatus.idle => [
          Tooltip(
            message: 'Start recording (Space)',
            child: FilledButton.icon(
              style: fill,
              onPressed: c.start,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Record'),
            ),
          ),
        ],
      RecStatus.recording => [
          Tooltip(
            message: 'Pause (Space)',
            child: FilledButton.tonalIcon(
              style: fill,
              onPressed: c.pause,
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
            ),
          ),
          stop(),
        ],
      RecStatus.paused => [
          Tooltip(
            message: 'Resume (Space)',
            child: FilledButton.icon(
              style: fill,
              onPressed: c.resume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
            ),
          ),
          stop(),
        ],
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          if (rec.status == RecStatus.recording)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.circle, size: 12, color: theme.colorScheme.error),
            ),
          Text(
            switch (rec.status) {
              RecStatus.idle => 'Ready to ride',
              RecStatus.paused => 'Paused  ${clock(rec.elapsed)}',
              RecStatus.recording => clock(rec.elapsed),
            },
            style: rec.status == RecStatus.idle
                ? theme.textTheme.titleMedium
                : theme.textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
          ),
          const Spacer(),
          Wrap(spacing: 8, children: controls),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

enum _StopChoice { save, discard, keepGoing }
