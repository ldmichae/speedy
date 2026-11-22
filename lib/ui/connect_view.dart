import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/trainer.dart';
import 'heart_rate_controller.dart';
import 'shifter_controller.dart';
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
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const _HeartRateSection(),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const _ShifterSection(),
      ],
    );
  }
}

/// Optional Zwift Click, Play or Ride for virtual shifting on routes.
class _ShifterSection extends ConsumerWidget {
  const _ShifterSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shifterControllerProvider);
    final c = ref.read(shifterControllerProvider.notifier);
    final theme = Theme.of(context);
    final busy = s.status == TrainerStatus.connecting;
    final connected = s.status == TrainerStatus.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Zwift shifters (optional)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Pair a Zwift Click, Play or Ride to change virtual gears while a '
          'route simulates the road. Update its firmware in Zwift Companion '
          'first, and close Zwift so only this app is connected.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (connected)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_input_component),
            title: Text(s.deviceName ?? 'Zwift shifters'),
            subtitle: const Text('Connected'),
            trailing: TextButton(
                onPressed: c.disconnect, child: const Text('Disconnect')),
          )
        else
          OutlinedButton.icon(
            onPressed: busy || s.scanning ? null : c.scan,
            icon: const Icon(Icons.settings_input_component),
            label: Text(busy
                ? 'Connecting to ${s.deviceName ?? 'shifters'}…'
                : s.scanning
                    ? 'Scanning…'
                    : 'Find Zwift shifters'),
          ),
        if (!kIsWeb && !connected && s.scanResults.isNotEmpty)
          for (final r in s.scanResults)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_input_component),
              title: Text(r.name),
              onTap: busy ? null : () => c.connectTo(r),
            ),
        if (s.error != null) ...[
          const SizedBox(height: 8),
          Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

/// Optional heart rate strap, connected separately from the trainer.
class _HeartRateSection extends ConsumerWidget {
  const _HeartRateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(heartRateControllerProvider);
    final c = ref.read(heartRateControllerProvider.notifier);
    final theme = Theme.of(context);
    final busy = s.status == TrainerStatus.connecting;
    final connected = s.status == TrainerStatus.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Heart rate monitor (optional)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Wake your strap by putting it on, then connect it here. Its reading '
          "replaces any heart rate the trainer reports.",
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (connected)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.favorite, color: Colors.red),
            title: Text(s.deviceName ?? 'Heart rate monitor'),
            subtitle: Text(s.bpm == null ? 'Waiting for a reading…' : '${s.bpm} bpm'),
            trailing: TextButton(
                onPressed: c.disconnect, child: const Text('Disconnect')),
          )
        else
          OutlinedButton.icon(
            onPressed: busy || s.scanning ? null : c.scan,
            icon: const Icon(Icons.favorite_border),
            label: Text(busy
                ? 'Connecting to ${s.deviceName ?? 'strap'}…'
                : s.scanning
                    ? 'Scanning…'
                    : 'Find heart rate monitor'),
          ),
        if (!kIsWeb && !connected && s.scanResults.isNotEmpty)
          for (final r in s.scanResults)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.favorite_border),
              title: Text(r.name),
              onTap: busy ? null : () => c.connectTo(r),
            ),
        if (s.error != null) ...[
          const SizedBox(height: 8),
          Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
