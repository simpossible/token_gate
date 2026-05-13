import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrl = 'http://127.0.0.1:12124';

class UpdateService {
  Future<String?> checkNewVersion(String deviceId, String platform) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/new_version').replace(
        queryParameters: {
          'device_id': deviceId,
          'platform': platform,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] != 0) return null;

      final data = json['data'] as Map<String, dynamic>;
      final version = data['version'] as String?;
      if (version == null || version.isEmpty) return null;
      return version;
    } catch (_) {
      return null;
    }
  }
}
