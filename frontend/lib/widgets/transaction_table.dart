import 'package:flutter/material.dart';
import '../models/transaction.dart';

class TransactionTable extends StatelessWidget {
  final List<Transaction> transactions;

  const TransactionTable({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (transactions.isEmpty) {
      return Center(
        child: Text('No transactions',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        columnSpacing: 20,
        headingTextStyle: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
        columns: const [
          DataColumn(label: Text('TIMESTAMP')),
          DataColumn(label: Text('TYPE')),
          DataColumn(label: Text('AMOUNT'), numeric: true),
          DataColumn(label: Text('DEST')),
          DataColumn(label: Text('FRAUD')),
        ],
        rows: transactions
            .map(
              (t) => DataRow(cells: [
                DataCell(Text(
                  _formatTs(t.timestamp),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                )),
                DataCell(_TypeChip(type: t.type)),
                DataCell(Text(
                  '₹${t.amount.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                )),
                DataCell(Text(
                  t.destId,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                )),
                DataCell(
                  Icon(
                    t.isFraud
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: t.isFraud
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF22C55E),
                    size: 16,
                  ),
                ),
              ]),
            )
            .toList(),
      ),
    );
  }

  String _formatTs(String ts) {
    try {
      final dt = DateTime.parse(ts);
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return ts.length > 16 ? ts.substring(0, 16) : ts;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  static Color _color(String t) {
    switch (t.toUpperCase()) {
      case 'TRANSFER': return const Color(0xFF3B82F6);
      case 'CASH_OUT': return const Color(0xFFEF4444);
      case 'PAYMENT': return const Color(0xFF22C55E);
      case 'CASH_IN': return const Color(0xFF8B5CF6);
      default: return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Text(type,
          style: TextStyle(
              color: c, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}