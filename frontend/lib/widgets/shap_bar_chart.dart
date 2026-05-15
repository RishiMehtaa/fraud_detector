import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ShapBarChart extends StatelessWidget {
  final Map<String, double> shapValues;

  const ShapBarChart({super.key, required this.shapValues});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (shapValues.isEmpty) {
      return const Center(child: Text('No SHAP data available'));
    }

    // Sort by absolute value descending
    final sorted = shapValues.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    final maxAbs = sorted.fold(0.0, (m, e) => m > e.value.abs() ? m : e.value.abs());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Feature Contributions',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...sorted.map((e) {
          final isPositive = e.value >= 0;
          final color = isPositive
              ? const Color(0xFFEF4444)
              : const Color(0xFF22C55E);
          final fraction = maxAbs > 0 ? e.value.abs() / maxAbs : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        e.key,
                        style: theme.textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        return Stack(
                          children: [
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Container(
                              height: 16,
                              width: constraints.maxWidth * fraction,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${isPositive ? '+' : ''}${e.value.toStringAsFixed(3)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: color, fontFamily: 'monospace'),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(width: 10, height: 10,
                decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('Increases risk',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 16),
            Container(width: 10, height: 10,
                decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('Decreases risk',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}