import 'package:flutter/material.dart';

/// The big number on every tile.
const metricNumberStyle = TextStyle(
  fontSize: 48,
  fontWeight: FontWeight.w600,
  height: 1.0,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// A labelled number that fills whatever space it is given: the number scales
/// up as the tile grows and down as it shrinks. Tabular figures keep digits
/// from jittering as values change.
///
/// A [note] explains a blank or unusual value ("No sensor", "Add profile").
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.note,
  });

  final String label;
  final String value;
  final String unit;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value, style: metricNumberStyle),
                    const SizedBox(width: 6),
                    // A blank value has no use for its unit, so the reason
                    // takes its place and scales with the number.
                    Text(
                      note ?? unit,
                      style: note == null
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
