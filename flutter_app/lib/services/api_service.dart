import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';

class ApiService {
  // Chrome on this PC: 127.0.0.1. Android emulator: 10.0.2.2.
  // Physical phone: replace with your computer's LAN IP address.
  static const String baseUrl = 'http://127.0.0.1:8000';
  static const Duration timeout = Duration(seconds: 20);

  static Future<dynamic> _decode(http.Response response) async {
    final body = response.body.isEmpty ? '{}' : response.body;
    final data = jsonDecode(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? data['detail'] ?? body : body;
      throw Exception(detail.toString());
    }
    return data;
  }

  static Future<bool> health() async {
    final response =
        await http.get(Uri.parse('$baseUrl/health')).timeout(timeout);
    return response.statusCode == 200;
  }

  static Future<List<SpendlyTransaction>> getTransactions() async {
    final response =
        await http.get(Uri.parse('$baseUrl/transactions')).timeout(timeout);
    final data = await _decode(response) as List;
    return data
        .map((item) =>
            SpendlyTransaction.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<SpendlyTransaction> addTransaction(
      SpendlyTransaction item) async {
    final response = await http
        .post(Uri.parse('$baseUrl/transactions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(item.toJson()))
        .timeout(timeout);
    return SpendlyTransaction.fromJson(await _decode(response));
  }

  static Future<SpendlyTransaction> updateTransaction(
      SpendlyTransaction item) async {
    final response = await http
        .put(Uri.parse('$baseUrl/transactions/${item.id}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(item.toJson()))
        .timeout(timeout);
    return SpendlyTransaction.fromJson(await _decode(response));
  }

  static Future<void> deleteTransaction(String id) async {
    final response = await http
        .delete(Uri.parse('$baseUrl/transactions/$id'))
        .timeout(timeout);
    await _decode(response);
  }

  static Future<Map<String, dynamic>> getAnalytics() async {
    final response =
        await http.get(Uri.parse('$baseUrl/analytics')).timeout(timeout);
    return Map<String, dynamic>.from(await _decode(response));
  }

  static Future<Map<String, dynamic>> getSmartInsights() async {
    final response =
        await http.get(Uri.parse('$baseUrl/insights')).timeout(timeout);
    return Map<String, dynamic>.from(await _decode(response));
  }

  static Future<Map<String, dynamic>> getSpendingForecast() async {
    final response =
        await http.get(Uri.parse('$baseUrl/forecast')).timeout(timeout);
    return Map<String, dynamic>.from(await _decode(response));
  }

  static Future<Map<String, dynamic>> getAnomalies() async {
    final response =
        await http.get(Uri.parse('$baseUrl/anomalies')).timeout(timeout);
    return Map<String, dynamic>.from(await _decode(response));
  }

  static Future<Map<String, dynamic>> getFinancialHealth() async {
    final response =
        await http.get(Uri.parse('$baseUrl/financial-health')).timeout(timeout);
    return Map<String, dynamic>.from(await _decode(response));
  }

  static Future<Map<String, dynamic>> getRecommendations() async {
    final response =
        await http.get(Uri.parse('$baseUrl/recommendations')).timeout(timeout);
    return Map<String, dynamic>.from(await _decode(response));
  }

  static Future<String> askOllama(String message) async {
    final response = await http
        .post(Uri.parse('$baseUrl/assistant/ollama'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': message}))
        .timeout(const Duration(seconds: 100));
    final data = await _decode(response) as Map<String, dynamic>;
    return data['answer']?.toString() ?? 'No response from Ollama.';
  }

  static Future<String> askAssistant(String message) async {
    return await askOllama(message);
  }
}
