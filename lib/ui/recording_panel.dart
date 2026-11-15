import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_recording.dart';
import 'format.dart';
import 'layout.dart';
import 'power_fun.dart';
import 'recorder_controller.dart';

/// Timer and record/pause/stop controls. Always visible, so starting a ride
/// does not move anything on screen.
class WorkoutBar extends ConsumerWidget {
  const WorkoutBar({super.key, this.trailing});

  /// Shown at the end of the row, after the controls.
  final Widget? trailing;

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final c = ref.read(recorderProvider.notifier);
    final summary = c.requestStop();
    if (summary == null) return;

    final choice = await showDialog<StopChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End ride?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RideStatRow(stats: summary.stats),
            const SizedBox(height: 12),
            PowerFun(joules: summary.joules, title: 'This ride'),
            const SizedBox(height: 12),
            Text('Saves to history and exports as '
                '${ref.read(rideFormatProvider).label} (change in Preferences).'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, StopChoice.keepGoing),
              child: const Text('Keep riding')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, StopChoice.discard),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, StopChoice.save),
              child: const Text('Save')),
        ],
      ),
    );
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await c.finish(choice ?? StopChoice.keepGoing, summary);
      if (path != null) {
        messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      // Recording is intact; the user can retry or discard.
      messenger.showSnackBar(SnackBar(
          content: Text("Couldn't save the ride ($e). Your recording is "
              'kept: press Stop to try again, or Discard.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(recorderProvider);
    final c = ref.read(recorderProvider.notifier);
    final theme = Theme.of(context);

    // One large control does Record, Pause and Resume (so does Space); Stop
    // stands apart from it, so a mis-tap on the big button never ends a ride.
    final touch = isTouchUi(context);
    final big = Size(0, touch ? 64 : 48);
    final label = theme.textTheme.titleMedium;

    final primary = switch (rec.status) {
      RecStatus.idle => Tooltip(
          message: 'Start recording (Space)',
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: big, textStyle: label),
            onPressed: c.start,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Record'),
          ),
        ),
      RecStatus.recording => Tooltip(
          message: 'Pause (Space)',
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: big, textStyle: label),
            onPressed: c.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
        ),
      RecStatus.paused => Tooltip(
          message: 'Resume (Space)',
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: big, textStyle: label),
            onPressed: c.resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
        ),
    };

    return Row(children: [
      Expanded(child: primary),
      if (rec.status != RecStatus.idle) ...[
        SizedBox(width: touch ? 24 : 12),
        Tooltip(
          message: 'Stop and save or discard',
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: Size(0, big.height)),
            onPressed: () => _stop(context, ref),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ),
      ],
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ]);
  }
}
