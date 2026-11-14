import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_stats.dart';
import '../core/units.dart';
import 'units_controller.dart';

String clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String rideTitle(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}'
      ' · ${two(d.hour)}:${two(d.minute)}';
}

/// Time, distance, average power and energy for a ride, in the user's ride
/// units.
class RideStatRow extends ConsumerWidget {
  const RideStatRow({super.key, required this.stats});

  final RideStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(rideUnitsProvider);
    final theme = Theme.of(context);
    Widget block(String label, String value, String unit) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text.rich(TextSpan(children: [
                TextSpan(text: value, style: theme.textTheme.titleLarge),
                if (unit.isNotEmpty)
                  TextSpan(text: ' $unit', style: theme.textTheme.bodySmall),
              ])),
            ],
          ),
        );
    return Row(children: [
      block('Time', clock(stats.duration), ''),
      block('Distance', distanceIn(stats.distanceKm, units).toStringAsFixed(1),
          distanceUnit(units)),
      block('Avg power', stats.avgPower?.round().toString() ?? '—', 'W'),
      block('Energy', stats.kcal?.round().toString() ?? '—', 'kcal'),
    ]);
  }
}
