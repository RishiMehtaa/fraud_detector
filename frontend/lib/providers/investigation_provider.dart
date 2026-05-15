import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';

final investigationProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, accountId) async {
  return ApiClient.instance.getAccount(accountId);
});