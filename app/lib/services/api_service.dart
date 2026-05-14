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
  if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  return jsonDecode(res.body) as Map<String, dynamic>;
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
  if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
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
  if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<void> _delete(String path) async {
  final res = await http
      .delete(Uri.parse('$_base$path'))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
}

List<T> _extractList<T>(
    Map<String, dynamic> json, String key, T Function(Map<String, dynamic>) fromJson) {
  final list = json[key] as List<dynamic>? ?? [];
  return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
}

class ApiService {
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

  Future<String?> getBuildID() async {
    try {
      final json = await _get('/api/version');
      return json['build_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Agents — returns {"agents": [...]}
  Future<List<Agent>> listAgents() async {
    final json = await _get('/api/agents');
    return _extractList(json, 'agents', Agent.fromJson);
  }

  // Configs — returns {"configs": [...]}
  Future<List<TokenConfig>> listConfigs(String agentType) async {
    final json = await _get('/api/configs?agent_type=$agentType');
    return _extractList(json, 'configs', TokenConfig.fromJson);
  }

  Future<TokenConfig> getConfig(String id) async {
    final json = await _get('/api/configs/$id');
    return TokenConfig.fromJson(json);
  }

  Future<TokenConfig> createConfig(Map<String, dynamic> body) async {
    final json = await _post('/api/configs', body);
    return TokenConfig.fromJson(json);
  }

  Future<TokenConfig> updateConfig(String id, Map<String, dynamic> body) async {
    final json = await _put('/api/configs/$id', body);
    return TokenConfig.fromJson(json);
  }

  Future<void> deleteConfig(String id) => _delete('/api/configs/$id');

  Future<void> activateConfig(String id) => _post('/api/configs/$id/activate');

  Future<void> deactivateConfig(String id) => _post('/api/configs/$id/deactivate');

  // Usage stats — returns flat UsageResponse object
  Future<UsageStats> getUsageStats(String configId) async {
    final json = await _get('/api/configs/$configId/usage');
    return UsageStats.fromJson(json);
  }

  // Usage history — GET /api/configs/:id/usages, returns {"usages": [...]}
  Future<List<UsageEntry>> getUsages(String configId, {int days = 7}) async {
    final json = await _get('/api/configs/$configId/usages?days=$days');
    return _extractList(json, 'usages', UsageEntry.fromJson);
  }

  // Usage delta — GET /api/configs/:id/usages/delta?after=ts, returns {"usages": [...]}
  Future<List<UsageEntry>> getUsageDelta(String configId, int afterTs) async {
    final json = await _get('/api/configs/$configId/usages/delta?after=$afterTs');
    return _extractList(json, 'usages', UsageEntry.fromJson);
  }

  // Latest latency — GET /api/configs/:id/latency/latest, returns single object
  Future<LatestLatencyResponse> getLatestLatency(String configId) async {
    final json = await _get('/api/configs/$configId/latency/latest');
    return LatestLatencyResponse.fromJson(json);
  }

  // Companies — returns {"list": [...]}
  Future<List<Company>> listCompanies() async {
    final json = await _get('/api/companies');
    final list = json['list'] as List<dynamic>? ?? [];
    return list.map((e) => Company.fromJson(e as Map<String, dynamic>)).toList();
  }
}
