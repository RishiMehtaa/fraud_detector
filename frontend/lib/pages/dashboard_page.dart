import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alert.dart';
import '../providers/alerts_provider.dart';
import '../widgets/kpi_card.dart';
import '../widgets/risk_badge.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsProvider);
    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (alerts) => _DashboardContent(alerts: alerts),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final List<Alert> alerts;
  const _DashboardContent({required this.alerts});

  Map<String, int> _patternFrequency() {
    final freq = <String, int>{};
    for (final a in alerts) {
      for (final p in a.triggeredPatterns) {
        freq[p] = (freq[p] ?? 0) + 1;
      }
    }
    return freq;
  }

  String _topPattern() {
    final freq = _patternFrequency();
    if (freq.isEmpty) return '—';
    return freq.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  double _totalAmount() =>
      alerts.fold(0.0, (sum, a) => sum + a.amount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highRisk = alerts.where((a) => a.riskScore > 70).length;
    final freq = _patternFrequency();
    final colors = [
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFFF59E0B),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFF22C55E),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Real-time fraud signal summary',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),

          // KPI row
          LayoutBuilder(builder: (ctx, constraints) {
            final w = (constraints.maxWidth - 48) / 4;
            return Row(
              children: [
                SizedBox(
                  width: w,
                  child: KpiCard(
                    label: 'Total Alerts',
                    value: alerts.length.toString(),
                    color: const Color(0xFF3B82F6),
                    icon: Icons.notifications_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: w,
                  child: KpiCard(
                    label: 'High Risk (>70)',
                    value: highRisk.toString(),
                    color: const Color(0xFFEF4444),
                    icon: Icons.warning_amber_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: w,
                  child: KpiCard(
                    label: 'Suspicious Volume',
                    value:
                        '₹${(_totalAmount() / 1e6).toStringAsFixed(1)}M',
                    color: const Color(0xFFF97316),
                    icon: Icons.currency_rupee,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: w,
                  child: KpiCard(
                    label: 'Top Pattern',
                    value: _topPattern(),
                    color: const Color(0xFF8B5CF6),
                    icon: Icons.pattern,
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: 32),

          // Charts row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pie chart
              Expanded(
                flex: 2,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pattern Frequency',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 220,
                          child: freq.isEmpty
                              ? const Center(child: Text('No patterns detected'))
                              : PieChart(PieChartData(
                                  sectionsSpace: 3,
                                  centerSpaceRadius: 50,
                                  sections: freq.entries
                                      .toList()
                                      .asMap()
                                      .entries
                                      .map((e) => PieChartSectionData(
                                            value: e.value.value.toDouble(),
                                            color: colors[
                                                e.key % colors.length],
                                            radius: 55,
                                            title:
                                                '${e.value.value}',
                                            titleStyle: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ))
                                      .toList(),
                                )),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: freq.entries
                              .toList()
                              .asMap()
                              .entries
                              .map((e) => Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: colors[
                                              e.key % colors.length],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(e.value.key,
                                          style: theme.textTheme.labelSmall),
                                    ],
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Top alerts list
              Expanded(
                flex: 3,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top Risk Accounts',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        ...alerts
                            .take(8)
                            .map((a) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(a.accountId,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                    fontFamily:
                                                        'monospace')),
                                      ),
                                      RiskBadge(
                                          score: a.riskScore,
                                          compact: true),
                                      const SizedBox(width: 12),
                                      Text(
                                        a.triggeredPatterns.isNotEmpty
                                            ? a.triggeredPatterns.first
                                            : '—',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                )),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}