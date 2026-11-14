import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_record.dart';
import 'format.dart';
import 'ride_chart.dart';
import 'ride_history_provider.dart';
import 'units_controller.dart';

/// App bar button that opens [HistoryScreen].
class HistoryButton extends StatelessWidget {
  const HistoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Ride history',
      icon: const Icon(Icons.history),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
      ),
    );
  }
}

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(rideHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ride history')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: rides.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load rides: $e')),
              data: (list) => list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No rides yet. Record a ride and save it to see it here.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _RideCard(ride: list[i]),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks before deleting [ride] from history. Returns true only if it was
/// deleted; a failure is reported in a snackbar and returns false.
Future<bool> confirmAndDeleteRide(
    BuildContext context, WidgetRef ref, RideRecord ride) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this ride?'),
      content: Text('${rideTitle(ride.startedAt)} will be removed from '
          'history. This cannot be undone.\n\n'
          'The CSV or FIT file you exported is not deleted.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await ref.read(rideHistoryStoreProvider).delete(ride.id);
    ref.invalidate(rideHistoryProvider);
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    return false;
  }
}

class _RideCard extends ConsumerWidget {
  const _RideCard({required this.ride});

  final RideRecord ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RideDetailScreen(ride: ride)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(rideTitle(ride.startedAt),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Delete ride',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => confirmAndDeleteRide(context, ref, ride),
                ),
              ]),
              const SizedBox(height: 4),
              RideStatRow(stats: ride.stats),
            ],
          ),
        ),
      ),
    );
  }
}

/// A saved ride, laid out like the live recording view: stats on top, then
/// the chart with the same metric toggles. The chart always shows the whole
/// ride, so the live view's time-window setting is not applied.
class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key, required this.ride});

  final RideRecord ride;

  /// After a delete: back to the list if other rides remain, else to home.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    if (!await confirmAndDeleteRide(context, ref, ride)) return;
    var others = true;
    try {
      others = (await ref.read(rideHistoryProvider.future)).isNotEmpty;
    } catch (_) {} // can't tell: the list screen shows the error
    if (others) {
      navigator.pop();
    } else {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(chartSettingsProvider).copyWith(clearWindow: true);
    return Scaffold(
      appBar: AppBar(
        title: Text(rideTitle(ride.startedAt)),
        actions: [
          IconButton(
            tooltip: 'Delete ride',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RideStatRow(stats: ride.stats),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 240,
                          child: RideChart(
                            samples: ride.samples,
                            settings: settings,
                            units: ref.watch(rideUnitsProvider),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ChartOptions(settings: settings, showWindow: false),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
