import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/graph_provider.dart';
import '../widgets/graph_canvas.dart';
import '../widgets/risk_badge.dart';

class NetworkGraphPage extends ConsumerStatefulWidget {
  const NetworkGraphPage({super.key});

  @override
  ConsumerState<NetworkGraphPage> createState() => _NetworkGraphPageState();
}

class _NetworkGraphPageState extends ConsumerState<NetworkGraphPage> {
  GraphNode? _selectedNode;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(defaultGraphProvider);
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _selectedNode != null
          ? _NodeDrawer(
              node: _selectedNode!,
              onClose: () {
                setState(() => _selectedNode = null);
                Navigator.of(context).pop();
              },
              onInvestigate: () {
                Navigator.of(context).pop();
                context.push('/investigation/${_selectedNode!.id}');
              },
            )
          : null,
      body: graphAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final nodes = (data['nodes'] as List<dynamic>? ?? [])
              .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
              .toList();
          final edges = (data['edges'] as List<dynamic>? ?? [])
              .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
              .toList();

          return Stack(
            children: [
              // Dark background
              Container(color: const Color(0xFF0D0D1A)),
              GraphCanvas(
                nodes: nodes,
                edges: edges,
                onNodeTap: (node) {
                  setState(() => _selectedNode = node);
                  _scaffoldKey.currentState?.openEndDrawer();
                },
              ),
              // Legend overlay
              Positioned(
                top: 16,
                left: 16,
                child: Card(
                  color: const Color(0xCC1A1A2E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Risk Level',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white70,
                                letterSpacing: 1)),
                        const SizedBox(height: 8),
                        ...[
                          ('Critical >80', const Color(0xFFEF4444)),
                          ('High 60–80', const Color(0xFFF97316)),
                          ('Medium 30–60', const Color(0xFFF59E0B)),
                          ('Low <30', const Color(0xFF22C55E)),
                        ].map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                          color: e.$2,
                                          shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text(e.$1,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11)),
                                ],
                              ),
                            )),
                        const SizedBox(height: 6),
                        Text('${nodes.length} nodes  •  ${edges.length} edges',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10)),
                      ],
                    ),
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

class _NodeDrawer extends StatelessWidget {
  final GraphNode node;
  final VoidCallback onClose;
  final VoidCallback onInvestigate;

  const _NodeDrawer({
    required this.node,
    required this.onClose,
    required this.onInvestigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Account Detail',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    iconSize: 20),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(node.id,
                style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                node.accountType == 'M' ? 'Merchant Account' : 'Customer Account',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            RiskBadge(score: node.riskScore),
            const SizedBox(height: 16),
            _InfoRow(label: 'Total Volume',
                value: '₹${node.totalVolume.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            if (node.triggeredPatterns.isNotEmpty) ...[
              Text('Triggered Patterns',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: node.triggeredPatterns
                    .map((p) => Chip(
                          label: Text(p, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              const Color(0xFFEF4444).withOpacity(0.1),
                          side: BorderSide(
                              color:
                                  const Color(0xFFEF4444).withOpacity(0.3)),
                        ))
                    .toList(),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onInvestigate,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Investigate'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}