class Alert {
  final String accountId;
  final double riskScore;
  final List<String> triggeredPatterns;
  final Map<String, double> shapBreakdown;
  final String timestamp;
  final double amount;

  const Alert({
    required this.accountId,
    required this.riskScore,
    required this.triggeredPatterns,
    required this.shapBreakdown,
    required this.timestamp,
    required this.amount,
  });

  factory Alert.fromJson(Map<String, dynamic> j) => Alert(
        accountId: j['account_id'] as String,
        riskScore: (j['risk_score'] as num).toDouble(),
        triggeredPatterns: (j['triggered_patterns'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        shapBreakdown: (j['shap_breakdown'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        timestamp: j['timestamp'] as String? ?? '',
        amount: (j['amount'] as num? ?? 0).toDouble(),
      );
}