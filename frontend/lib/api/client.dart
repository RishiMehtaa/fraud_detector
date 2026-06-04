import 'package:dio/dio.dart';
import '../models/account.dart';
import '../models/alert.dart';
import '../models/transaction.dart';
import '../models/evidence.dart';

class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 60),
receiveTimeout: const Duration(seconds: 90),
      // connectTimeout: const Duration(seconds: 10),
      // receiveTimeout: const Duration(seconds: 30),
    ));
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  // GET /graph
  Future<Map<String, dynamic>> getGraph({
    int page = 1,
    int limit = 100,
    double minRisk = 0,
  }) async {
    final r = await _dio.get('/graph', queryParameters: {
      'page': page,
      'limit': limit,
      'min_risk': minRisk,
    });
    return r.data as Map<String, dynamic>;
  }

  // GET /alerts
  Future<List<Alert>> getAlerts() async {
    final r = await _dio.get('/alerts');
    return (r.data as List<dynamic>)
        .map((e) => Alert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // GET /account/{id}
  Future<Map<String, dynamic>> getAccount(String id) async {
    final r = await _dio.get('/account/$id');
    return r.data as Map<String, dynamic>;
  }

  // GET /trace/{source}/{dest}
  Future<List<dynamic>> getTrace(String source, String dest) async {
    final r = await _dio.get('/trace/$source/$dest');
    final data = r.data as Map<String, dynamic>;
    return data['paths'] as List<dynamic>;
  }

  // POST /explain/{id}
  Future<String> explainAccount(String id) async {
    final r = await _dio.post('/explain/$id');
    return (r.data as Map<String, dynamic>)['narrative'] as String;
  }

  // GET /evidence/{id}
  Future<Evidence> getEvidence(String id) async {
    final r = await _dio.get('/evidence/$id');
    return Evidence.fromJson(r.data as Map<String, dynamic>);
  }

  // POST /chat
  Future<Map<String, dynamic>> sendChat(
      String question, {
      String? preset,
      }) async {
    final r = await _dio.post('/chat', data: {
      'question': question,
      if (preset != null) 'preset': preset,
    });
    return r.data as Map<String, dynamic>;
  }
}