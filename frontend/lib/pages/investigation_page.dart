// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../models/transaction.dart';
import '../providers/investigation_provider.dart';
import '../widgets/graph_canvas.dart';
import '../widgets/risk_badge.dart';
import '../widgets/shap_bar_chart.dart';
import '../widgets/transaction_table.dart';

class InvestigationPage extends ConsumerStatefulWidget {
  final String accountId;
  const InvestigationPage({super.key, required this.accountId});

  @override
  ConsumerState<InvestigationPage> createState() => _InvestigationPageState();
}

class _InvestigationPageState extends ConsumerState<InvestigationPage> {
  String? _narrative;
  bool _narrativeLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNarrative();
  }

  Future<void> _fetchNarrative() async {
    setState(() => _narrativeLoading = true);
    try {
      final n = await ApiClient.instance.explainAccount(widget.accountId);
      setState(() {
        _narrative = n;
        _narrativeLoading = false;
      });
    } catch (_) {
      setState(() {
        _narrative = 'Narrative unavailable.';
        _narrativeLoading = false;
      });
    }
  }

  Future<void> _exportEvidence() async {
    try {
      final evidence = await ApiClient.instance.getEvidence(widget.accountId);
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(evidence.toJson());
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'evidence_${widget.accountId}_${DateTime.now().millisecondsSinceEpoch}.json')
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataAsync = ref.watch(investigationProvider(widget.accountId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountId,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
        actions: [
          FilledButton.icon(
            onPressed: _exportEvidence,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Export Evidence'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final nodes = (data['nodes'] as List<dynamic>? ?? [])
              .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
              .toList();
          final edges = (data['edges'] as List<dynamic>? ?? [])
              .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
              .toList();
          final txns = (data['transactions'] as List<dynamic>? ?? [])
              .map((e) =>
                  Transaction.fromJson(e as Map<String, dynamic>))
              .toList();
          final shap =
              (data['shap_breakdown'] as Map<String, dynamic>? ?? {})
                  .map((k, v) => MapEntry(k, (v as num).toDouble()));
          final riskScore =
              (data['risk_score'] as num? ?? 0).toDouble();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: subgraph 40%
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Text('2-Hop Network',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          RiskBadge(score: riskScore),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0D1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GraphCanvas(nodes: nodes, edges: edges),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Right: 60%
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                  child: Column(
                    children: [
                      // SHAP
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ShapBarChart(shapValues: shap),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // LLM Narrative
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome,
                                      size: 15,
                                      color: Color(0xFF8B5CF6)),
                                  const SizedBox(width: 6),
                                  Text('AI Analysis',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _narrativeLoading
                                  ? const SizedBox(
                                      height: 32,
                                      child: Center(
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2)))
                                  : Text(
                                      _narrative ?? '',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontStyle: FontStyle.italic,
                                              height: 1.5),
                                    ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Transactions
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Transaction Timeline',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              TransactionTable(transactions: txns),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}