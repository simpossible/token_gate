import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'api_service.dart';
import 'log_service.dart';

class BackendService {
  final ApiService _api;
  final LogService _log;
  BackendService(this._api, this._log);

  Future<String> _loadExpectedBuildID() async {
    try {
      return (await rootBundle.loadString('assets/bin/build_id.txt')).trim();
    } catch (_) {
      return 'dev';
    }
  }

  Future<void> ensureRunning() async {
    final expectedID = await _loadExpectedBuildID();

    if (await _api.isAlive()) {
      final remoteID = await _api.getBuildID();
      if (remoteID != null && remoteID == expectedID) {
        _log.info('BackendService', 'daemon already running (buildID=$remoteID)');
        return;
      }
      _log.info('BackendService', 'daemon buildID mismatch (remote=$remoteID, expected=$expectedID), restarting...');
      await _killDaemon();
    }
    _log.info('BackendService', 'daemon not running, starting...');
    await _startDaemon();
    await _waitReady();
    _log.info('BackendService', 'daemon started successfully');
  }

  Future<void> _killDaemon() async {
    try {
      await Process.run('pkill', ['-f', 'token_gate.*--daemon']);
      _log.info('BackendService', 'killed old daemon');
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.error('BackendService', 'failed to kill daemon', e);
    }
  }

  Future<void> _startDaemon() async {
    final binPath = _bundleBinaryPath();
    if (!File(binPath).existsSync()) {
      _log.error('BackendService', 'binary not found: $binPath');
      throw Exception('token_gate binary not found in bundle: $binPath');
    }
    _log.info('BackendService', 'starting daemon from: $binPath');
    await Process.start(binPath, [], mode: ProcessStartMode.detached);
  }

  String _bundleBinaryPath() {
    final exePath = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      final contentsDir = exePath.substring(0, exePath.lastIndexOf('/MacOS/'));
      return '$contentsDir/Resources/token_gate';
    } else if (Platform.isWindows) {
      final exeDir = exePath.substring(0, exePath.lastIndexOf(r'\'));
      return '$exeDir\\token_gate.exe';
    } else {
      final exeDir = exePath.substring(0, exePath.lastIndexOf('/'));
      return '$exeDir/token_gate';
    }
  }

  Future<void> _waitReady({int maxAttempts = 25}) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (await _api.isAlive()) return;
    }
    _log.error('BackendService', 'daemon did not start within 5 seconds');
    throw Exception('token_gate daemon did not start within 5 seconds');
  }
}
