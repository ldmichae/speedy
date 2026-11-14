import 'package:flutter/material.dart';

import '../core/power_fun.dart';

/// Energy produced, with playful equivalents. Hidden when there is none.
class PowerFun extends StatelessWidget {
  const PowerFun({super.key, required this.joules, this.title = 'Power produced'});

  final double joules;
  final String title;

  @override
  Widget build(BuildContext context) {
    final facts = funFacts(joules);
    if (facts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.labelLarge),
      Text(energyText(joules),
          style: theme.textTheme.headlineSmall
              ?.copyWith(color: theme.colorScheme.primary)),
      const SizedBox(height: 4),
      Text('Enough to', style: theme.textTheme.bodySmall),
      for (final f in facts) Text('• $f', style: theme.textTheme.bodyMedium),
    ]);
  }
}
