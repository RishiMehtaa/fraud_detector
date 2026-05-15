import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';

final graphProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, Map<String, dynamic>>((ref, params) async {
  return ApiClient.instance.getGraph(
    page: params['page'] as int? ?? 1,
    limit: params['limit'] as int? ?? 100,
    minRisk: (params['min_risk'] as num? ?? 0).toDouble(),
  );
});

// Default graph with no filters
final defaultGraphProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ApiClient.instance.getGraph(limit: 200);
});