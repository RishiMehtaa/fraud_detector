import 'package:flutter/material.dart';

import '../api/client.dart';

class FundFlowTracePage extends StatefulWidget {
  const FundFlowTracePage({super.key});

  @override
  State<FundFlowTracePage> createState() => _FundFlowTracePageState();
}

class _FundFlowTracePageState extends State<FundFlowTracePage> {
  final _srcCtrl = TextEditingController();
  final _dstCtrl = TextEditingController();
  List<dynamic> _paths = [];
  bool _loading = false;
  String? _error;

  Future<void> _trace() async {
    final src = _srcCtrl.text.trim();
    final dst = _dstCtrl.text.trim();
    if (src.isEmpty || dst.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _paths = [];
    });
    try {
      final result = await ApiClient.instance.getTrace(src, dst);
      setState(() {
        _paths = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _srcCtrl.dispose();
    _dstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fund Flow Trace',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Find all paths between two accounts (max 6 hops)',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),

          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _srcCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Source Account',
                    hintText: 'e.g. C1234567890',
                    prefixIcon: Icon(Icons.account_circle_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              Expanded(
                child: TextField(
                  controller: _dstCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Destination Account',
                    hintText: 'e.g. C9876543210',
                    prefixIcon: Icon(Icons.account_circle),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _trace,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Trace'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text('Error: $_error',
                style: TextStyle(color: theme.colorScheme.error)),
          if (_paths.isEmpty && !_loading && _error == null && _srcCtrl.text.isNotEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Icon(Icons.search_off,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant
                          .withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text('No paths found',
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),

          // Paths
          ..._paths.asMap().entries.map((entry) {
            final idx = entry.key;
            final path = entry.value as List<dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side:
                      BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Path ${idx + 1}  •  ${path.length} hops',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              letterSpacing: 1)),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < path.length; i++) ...[
                              _HopChip(hop: path[i] as Map<String, dynamic>),
                              if (i < path.length - 1)
                                _ArrowLabel(
                                  amount: (path[i]['amount'] as num?)
                                          ?.toDouble() ??
                                      0,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HopChip extends StatelessWidget {
  final Map<String, dynamic> hop;
  const _HopChip({required this.hop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = hop['account_id'] as String? ?? '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
      ),
      child: Text(id,
          style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer)),
    );
  }
}

class _ArrowLabel extends StatelessWidget {
  final double amount;
  const _ArrowLabel({required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text('₹${(amount / 1000).toStringAsFixed(1)}K',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9)),
          const Icon(Icons.arrow_forward, size: 16),
        ],
      ),
    );
  }
}