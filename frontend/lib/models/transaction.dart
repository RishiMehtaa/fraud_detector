class Transaction {
  final String accountId;
  final String destId;
  final String type;
  final double amount;
  final String timestamp;
  final bool isFraud;

  const Transaction({
    required this.accountId,
    required this.destId,
    required this.type,
    required this.amount,
    required this.timestamp,
    required this.isFraud,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        accountId: j['account_id'] as String? ?? j['source'] as String? ?? '',
        destId: j['dest_id'] as String? ?? j['target'] as String? ?? '',
        type: j['type'] as String? ?? '',
        amount: (j['amount'] as num).toDouble(),
        timestamp: j['timestamp'] as String? ?? '',
        isFraud: j['is_fraud'] as bool? ?? false,
      );
}