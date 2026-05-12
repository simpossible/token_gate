import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/agent.dart';
import '../models/company.dart';
import '../models/latency_entry.dart';
import '../models/token_config.dart';
import '../models/usage_entry.dart';
import '../models/usage_stats.dart';

const _base = 'http://127.0.0.1:12122';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

Future<Map<String, dynamic>> _get(String path) async {
  final res = await http
      .get(Uri.parse('$_base$path'))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, res.body);
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<List<dynamic>> _getList(String path) async {
  final res = await http
      .get(Uri.parse('$_base$path'))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, res.body);
  }
  return jsonDecode(res.body) as List<dynamic>;
}

Future<Map<String, dynamic>> _post(String path,
    [Map<String, dynamic>? body]) async {
  final res = await http
      .post(
        Uri.parse('$_base$path'),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      )
      .timeout(const Duration(seconds: 10));
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, res.body);
  }
  if (res.body.isEmpty) return {};
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _put(
    String path, Map<String, dynamic> body) async {
  final res = await http
      .put(
        Uri.parse('$_base$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 10));
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, res.body);
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<void> _delete(String path) async {
  final res = await http
      .delete(Uri.parse('$_base$path'))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, res.body);
  }
}

class ApiService {
  // Health check — returns true if daemon is reachable
  Future<bool> isAlive() async {
    try {
      await http
          .get(Uri.parse('$_base/api/agents'))
          .timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  // Agents
  Future<List<Agent>> listAgents() async {
    final list = await _getList('/api/agents');
    return list.map((e) => Agent.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Configs
  Future<List<TokenConfig>> listConfigs(String agentType) async {
    final list = await _getList('/api/configs?agent_type=$agentType');
    return list
        .map((e) => TokenConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TokenConfig> getConfig(int id) async {
    final json = await _get('/api/configs/$id');
    return TokenConfig.fromJson(json);
  }

  Future<TokenConfig> createConfig(Map<String, dynamic> body) async {
    final json = await _post('/api/configs', body);
    return TokenConfig.fromJson(json);
  }

  Future<TokenConfig> updateConfig(int id, Map<String, dynamic> body) async {
    final json = await _put('/api/configs/$id', body);
    return TokenConfig.fromJson(json);
  }

  Future<void> deleteConfig(int id) => _delete('/api/configs/$id');

  Future<void> activateConfig(int id) => _post('/api/configs/$id/activate');

  Future<void> deactivateConfig(int id) => _post('/api/configs/$id/deactivate');

  // Usage
  Future<UsageStats> getUsageStats(int configId) async {
    final json = await _get('/api/configs/$configId/usage');
    return UsageStats.fromJson(json);
  }

  Future<List<UsageEntry>> getUsages({int? configId}) async {
    final query = configId != null ? '?config_id=$configId' : '';
    final list = await _getList('/api/usages$query');
    return list
        .map((e) => UsageEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UsageDelta> getUsageDelta() async {
    final json = await _get('/api/usage_delta');
    return UsageDelta.fromJson(json);
  }

  // Latency
  Future<List<LatencyEntry>> getLatestLatency() async {
    final list = await _getList('/api/latency/latest');
    return list
        .map((e) => LatencyEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Companies
  Future<List<Company>> listCompanies() async {
    final json = await _get('/api/companies');
    final list = (json['list'] as List<dynamic>? ?? []);
    return list
        .map((e) => Company.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
