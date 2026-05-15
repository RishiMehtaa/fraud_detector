import 'package:flutter/material.dart';

class RiskBadge extends StatelessWidget {
  final double score;
  final bool compact;

  const RiskBadge({super.key, required this.score, this.compact = false});

  static Color colorForScore(double score) {
    if (score < 30) return const Color(0xFF22C55E);
    if (score < 60) return const Color(0xFFF59E0B);
    if (score < 80) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  static String labelForScore(double score) {
    if (score < 30) return 'LOW';
    if (score < 60) return 'MEDIUM';
    if (score < 80) return 'HIGH';
    return 'CRITICAL';
  }

  @override
  Widget build(BuildContext context) {
    final color = colorForScore(score);
    final scoreInt = score.round();

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          '$scoreInt',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$scoreInt  ${labelForScore(score)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}