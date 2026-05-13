import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';

const _deviceIdKey = 'token_gate_device_id';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final deviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(_deviceIdKey);
  if (id == null) {
    id = _generateUUID();
    await prefs.setString(_deviceIdKey, id);
  }
  return id;
});

final newVersionProvider = StateProvider<String?>((ref) => null);

String _currentPlatform() {
  if (Platform.isMacOS) return 'mac';
  if (Platform.isWindows) return 'windows';
  return 'linux';
}

String _generateUUID() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

Future<void> checkForUpdate(WidgetRef ref) async {
  final deviceId = await ref.read(deviceIdProvider.future);
  if (deviceId == null) return;

  final service = ref.read(updateServiceProvider);
  final remoteVersion = await service.checkNewVersion(deviceId, _currentPlatform());
  if (remoteVersion == null) return;

  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersion = packageInfo.version;

  if (_isNewer(remoteVersion, currentVersion)) {
    ref.read(newVersionProvider.notifier).state = remoteVersion;
  }
}

bool _isNewer(String remote, String current) {
  final r = remote.split('.').map(int.parse).toList();
  final c = current.split('.').map(int.parse).toList();
  for (var i = 0; i < r.length && i < c.length; i++) {
    if (r[i] > c[i]) return true;
    if (r[i] < c[i]) return false;
  }
  return r.length > c.length;
}
