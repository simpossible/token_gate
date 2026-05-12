import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
    final binPath = await _extractBinary();
    // Go daemon daemonizes itself, no need to track the process
    await Process.start(binPath, [], mode: ProcessStartMode.detached);
  }

  Future<String> _extractBinary() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final dir = Directory('$home/.token_gate');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final dest = '$home/.token_gate/token_gate';
    final destFile = File(dest);

    final data = await rootBundle.load('assets/bin/token_gate');
    await destFile.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // chmod +x on Unix
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', dest]);
    }
    return dest;
  }

  Future<void> _waitReady({int maxAttempts = 25}) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (await _api.isAlive()) return;
    }
    throw Exception('token_gate daemon did not start within 5 seconds');
  }
}
