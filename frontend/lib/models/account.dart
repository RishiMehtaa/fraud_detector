class Account {
  final String accountId;
  final double totalVolume;
  final int txCount;
  final String accountType;
  final double avgAmount;
  final int degree;
  final double riskScore;
  final List<String> triggeredPatterns;

  const Account({
    required this.accountId,
    required this.totalVolume,
    required this.txCount,
    required this.accountType,
    required this.avgAmount,
    required this.degree,
    required this.riskScore,
    required this.triggeredPatterns,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        accountId: j['account_id'] as String,
        totalVolume: (j['total_volume'] as num).toDouble(),
        txCount: (j['tx_count'] as num).toInt(),
        accountType: j['account_type'] as String,
        avgAmount: (j['avg_amount'] as num).toDouble(),
        degree: (j['degree'] as num).toInt(),
        riskScore: (j['risk_score'] as num? ?? 0).toDouble(),
        triggeredPatterns: (j['triggered_patterns'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
      );
}