import 'dart:io';

import 'package:flutter/foundation.dart';

const _maxBytes = 5 * 1024 * 1024; // 5 MB
const _maxBackups = 2;

class LogService {
  static String get logDirPath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.token_gate/logs';
  }

  static String get logFilePath => '$logDirPath/flutter.log';

  IOSink? _sink;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = Directory(logDirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _rotateIfNeeded();
      final file = File(logFilePath);
      _sink = file.openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('[LogService] init failed: $e');
    }
  }

  void _rotateIfNeeded() {
    final file = File(logFilePath);
    if (!file.existsSync()) return;
    try {
      final size = file.lengthSync();
      if (size < _maxBytes) return;
      _sink?.close();
      _sink = null;
      // Shift backups: .log.2 → delete, .log.1 → .log.2, .log → .log.1
      for (var i = _maxBackups; i >= 1; i--) {
        final older = File('$logFilePath.$i');
        if (i == _maxBackups) {
          older.existsSync() ? older.deleteSync() : null;
        } else {
          if (older.existsSync()) {
            older.renameSync('$logFilePath.${i + 1}');
          }
        }
      }
      file.renameSync('$logFilePath.1');
    } catch (_) {}
  }

  Future<void> info(String tag, String message) async {
    await _write('INFO', tag, message);
  }

  Future<void> error(String tag, String message, [Object? error]) async {
    final buf = StringBuffer(message);
    if (error != null) buf.write(' | $error');
    await _write('ERROR', tag, buf.toString());
  }

  Future<void> _write(String level, String tag, String message) async {
    await _init();
    final now = DateTime.now();
    final ts =
        '${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")} '
        '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}.'
        '${now.millisecond.toString().padLeft(3, "0")}';
    final line = '$ts [$level] [$tag] $message';
    debugPrint(line);
    _sink?.writeln(line);
  }

  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
