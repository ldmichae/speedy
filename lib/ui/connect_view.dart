import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/trainer.dart';
import 'trainer_controller.dart';

class ConnectView extends ConsumerWidget {
  const ConnectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(trainerControllerProvider);
    final c = ref.read(trainerControllerProvider.notifier);
    final busy = s.status == TrainerStatus.connecting;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Connect your trainer', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          kIsWeb
              ? 'Pick your KICKR in the browser prompt. Web Bluetooth works in '
                  'Chrome and Edge.'
              : 'Turn on your KICKR, then scan. Close the Wahoo or Zwift app '
                  'first so only this app controls it.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy || s.scanning ? null : c.scan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(s.scanning ? 'Scanning…' : 'Find trainer'),
        ),
        if (busy) ...[
          const SizedBox(height: 24),
          Row(children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Connecting to ${s.deviceName ?? 'trainer'}…'),
          ]),
        ],
        if (!kIsWeb && s.scanResults.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Trainers found', style: theme.textTheme.titleMedium),
          for (final r in s.scanResults)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pedal_bike),
              title: Text(r.name),
              onTap: busy ? null : () => c.connectTo(r),
            ),
        ],
        if (s.error != null) ...[
          const SizedBox(height: 24),
          Text(
            s.error!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          Text(
            kIsWeb
                ? 'Check that Bluetooth is on and the trainer is awake, then '
                    'try Find trainer again.'
                : 'Check that Bluetooth is on, the trainer is awake, and no '
                    'other app is connected to it, then try again.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}
