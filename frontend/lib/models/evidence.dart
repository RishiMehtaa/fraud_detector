class Evidence {
  final String reportId;
  final String generatedAt;
  final String subjectAccount;
  final double riskScore;
  final List<String> triggeredPatterns;
  final List<Map<String, dynamic>> transactionTimeline;
  final List<String> connectedAccounts;
  final Map<String, double> shapBreakdown;
  final String llmNarrative;
  final String investigatorNotes;

  const Evidence({
    required this.reportId,
    required this.generatedAt,
    required this.subjectAccount,
    required this.riskScore,
    required this.triggeredPatterns,
    required this.transactionTimeline,
    required this.connectedAccounts,
    required this.shapBreakdown,
    required this.llmNarrative,
    required this.investigatorNotes,
  });

  factory Evidence.fromJson(Map<String, dynamic> j) => Evidence(
        reportId: j['report_id'] as String,
        generatedAt: j['generated_at'] as String,
        subjectAccount: j['subject_account'] as String,
        riskScore: (j['risk_score'] as num).toDouble(),
        triggeredPatterns: (j['triggered_patterns'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        transactionTimeline:
            (j['transaction_timeline'] as List<dynamic>? ?? [])
                .map((e) => e as Map<String, dynamic>)
                .toList(),
        connectedAccounts: (j['connected_accounts'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        shapBreakdown: (j['shap_breakdown'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        llmNarrative: j['llm_narrative'] as String? ?? '',
        investigatorNotes: j['investigator_notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'report_id': reportId,
        'generated_at': generatedAt,
        'subject_account': subjectAccount,
        'risk_score': riskScore,
        'triggered_patterns': triggeredPatterns,
        'transaction_timeline': transactionTimeline,
        'connected_accounts': connectedAccounts,
        'shap_breakdown': shapBreakdown,
        'llm_narrative': llmNarrative,
        'investigator_notes': investigatorNotes,
      };
}