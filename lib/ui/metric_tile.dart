import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// A labelled live number. Tabular figures keep digits from jittering as
/// values change.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.hero = false,
    this.footnote,
  });

  final String label;
  final String value;
  final String unit;
  final bool hero;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberStyle = TextStyle(
      fontSize: hero ? 96 : 36,
      fontWeight: hero ? FontWeight.w700 : FontWeight.w600,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: hero ? theme.colorScheme.primary : null,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(hero ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            SizedBox(height: hero ? 12 : 8),
            // Shrinks the number and unit rather than overflowing a narrow tile.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: numberStyle),
                  const SizedBox(width: 6),
                  Text(unit, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            if (footnote != null) ...[
              const SizedBox(height: 8),
              Text(footnote!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
