import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/fitness_stats.dart';
import '../core/units.dart';
import 'ride_history_provider.dart';
import 'units_controller.dart';

final dailyTotalsProvider = Provider<Map<DateTime, DayTotal>>((ref) =>
    dailyTotals(ref.watch(rideHistoryProvider).valueOrNull ?? const []));

/// Last-30-day totals and a month calendar with a dot on each riding day,
/// sized by how far that day's rides went.
class FitnessSummary extends ConsumerStatefulWidget {
  const FitnessSummary({super.key, this.now});

  /// Overridable for tests.
  final DateTime? now;

  @override
  ConsumerState<FitnessSummary> createState() => _FitnessSummaryState();
}

class _FitnessSummaryState extends ConsumerState<FitnessSummary> {
  late final DateTime _now = widget.now ?? DateTime.now();
  late DateTime _month = DateTime(_now.year, _now.month);

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(dailyTotalsProvider);
    final units = ref.watch(rideUnitsProvider);
    final total = last30Days(days, _now);
    final theme = Theme.of(context);

    Widget stat(String label, String value, Key key) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelMedium),
            Text(value, key: key, style: theme.textTheme.headlineSmall),
          ]),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            stat(
                'Distance, last 30 days',
                '${distanceIn(total.km, units).toStringAsFixed(1)} '
                    '${distanceUnit(units)}',
                const Key('distance30')),
            stat('Elevation gain, last 30 days',
                elevationText(total.gainMeters, units), const Key('gain30')),
          ]),
          const SizedBox(height: 4),
          Text('Elevation is recorded for route rides only.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          _MonthCalendar(
              month: _month, days: days, units: units, onShift: _shift),
        ]),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.days,
    required this.units,
    required this.onShift,
  });

  final DateTime month;
  final Map<DateTime, DayTotal> days;
  final UnitSystem units;
  final void Function(int months) onShift;

  static const _maxDot = 18.0;
  static const _minDot = 6.0;

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month);
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = (first.weekday % 7 - l10n.firstDayOfWeekIndex + 7) % 7;

    // Dots scale against the longest day shown so a month always uses the range.
    final kms = [
      for (var d = 1; d <= count; d++)
        days[DateTime(month.year, month.month, d)]?.km ?? 0.0
    ];
    final longest = kms.fold(0.0, (a, b) => b > a ? b : a);

    final order = [
      for (var i = 0; i < 7; i++) (l10n.firstDayOfWeekIndex + i) % 7
    ];
    return Column(children: [
      Row(children: [
        IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onShift(-1)),
        Expanded(
            child: Text(l10n.formatMonthYear(month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium)),
        IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onShift(1)),
      ]),
      Row(children: [
        for (final i in order)
          Expanded(
              child: Center(
                  child: Text(l10n.narrowWeekdays[i],
                      style: theme.textTheme.labelSmall))),
      ]),
      const SizedBox(height: 4),
      for (var week = 0; week * 7 < lead + count; week++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(child: _cell(context, week * 7 + col - lead + 1, count, kms, longest)),
        ]),
    ]);
  }

  Widget _cell(BuildContext context, int day, int count, List<double> kms,
      double longest) {
    if (day < 1 || day > count) return const SizedBox(height: 40);
    final km = kms[day - 1];
    final dot = km == 0
        ? const SizedBox.shrink()
        : Container(
            key: Key('dot$day'),
            width: _minDot + (_maxDot - _minDot) * km / longest,
            height: _minDot + (_maxDot - _minDot) * km / longest,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle),
          );
    return Tooltip(
      message: km == 0
          ? ''
          : '${distanceIn(km, units).toStringAsFixed(1)} ${distanceUnit(units)}',
      child: SizedBox(
        height: 40,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$day', style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: _maxDot, child: Center(child: dot)),
        ]),
      ),
    );
  }
}
