import 'dart:async';
import 'dart:io';

import 'api_service.dart';

class BackendService {
  final ApiService _api;
  BackendService(this._api);

  Future<void> ensureRunning() async {
    if (await _api.isAlive()) return;
    await _startDaemon();
    await _waitReady();
  }

  Future<void> _startDaemon() async {
    final binPath = _bundleBinaryPath();
    if (!File(binPath).existsSync()) {
      throw Exception('token_gate binary not found in bundle: $binPath');
    }
    await Process.start(binPath, [], mode: ProcessStartMode.detached);
  }

  /// Resolve the Go binary path from the app bundle:
  /// <app.app>/Contents/Resources/token_gate
  String _bundleBinaryPath() {
    final exePath = Platform.resolvedExecutable;
    // exePath = <app.app>/Contents/MacOS/<executable>
    final contentsDir = exePath.substring(0, exePath.lastIndexOf('/MacOS/'));
    return '$contentsDir/Resources/token_gate';
  }

  Future<void> _waitReady({int maxAttempts = 25}) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (await _api.isAlive()) return;
    }
    throw Exception('token_gate daemon did not start within 5 seconds');
  }
}
