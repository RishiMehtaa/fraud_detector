import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../models/alert.dart';

final alertsProvider = FutureProvider.autoDispose<List<Alert>>((ref) async {
  return ApiClient.instance.getAlerts();
});