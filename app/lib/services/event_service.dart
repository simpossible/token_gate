import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'log_service.dart';

const _base = 'http://127.0.0.1:12122';

class EventMessage {
  final String type;
  final Map<String, dynamic> data;

  EventMessage(this.type, this.data);
}

class EventConnection {
  final String connType;
  final String? configId;
  final LogService _log;
  http.Client? _client;
  StreamSubscription? _subscription;
  StreamController<EventMessage>? _controller;
  Timer? _reconnectTimer;
  bool _disposed = false;

  EventConnection({required this.connType, this.configId, required LogService log}) : _log = log;

  Stream<EventMessage> connect() {
    _controller = StreamController<EventMessage>.broadcast();
    _doConnect();
    return _controller!.stream;
  }

  void _doConnect() {
    if (_disposed) return;

    var url = '$_base/api/events?type=$connType';
    if (configId != null && configId!.isNotEmpty) {
      url += '&config_id=$configId';
    }

    _log.info('EventService', 'connecting to $url');
    _client = http.Client();
    final request = http.Request('GET', Uri.parse(url));

    _client!.send(request).then((streamedResponse) {
      _log.info('EventService', 'SSE connected: status=${streamedResponse.statusCode}, connType=$connType, configId=$configId');
      final stream = streamedResponse.stream;
      String buffer = '';
      String currentEvent = '';

      _subscription = stream.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          buffer += text;
          final lines = buffer.split('\n');
          buffer = lines.removeLast(); // keep incomplete line

          for (final line in lines) {
            if (line.startsWith('event: ')) {
              currentEvent = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              final dataStr = line.substring(6);
              _log.info('EventService', 'SSE event=$currentEvent data=$dataStr');
              try {
                final json = jsonDecode(dataStr) as Map<String, dynamic>;
                if (currentEvent.isNotEmpty && _controller != null && !_controller!.isClosed) {
                  _controller!.add(EventMessage(currentEvent, json));
                }
              } catch (e) {
                _log.error('EventService', 'SSE parse error', e);
              }
              currentEvent = '';
            } else if (line.trim().isEmpty) {
              currentEvent = '';
            }
          }
        },
        onError: (e) {
          _log.error('EventService', 'SSE stream error', e);
          _scheduleReconnect();
        },
        onDone: () {
          _log.info('EventService', 'SSE stream done (closed by server), reconnecting...');
          _scheduleReconnect();
        },
      );
    }).catchError((e) {
      _log.error('EventService', 'SSE connection failed', e);
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _log.info('EventService', 'reconnecting in 3s... (connType=$connType, configId=$configId)');
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _cleanup();
      _doConnect();
    });
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  void dispose() {
    _log.info('EventService', 'disposing connection: connType=$connType, configId=$configId');
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanup();
    _controller?.close();
  }
}

class EventService {
  final Map<String, EventConnection> _connections = {};
  final LogService _log;

  EventService(this._log);

  Stream<EventMessage> connect(String connType, {String? configId}) {
    final key = '${connType}_${configId ?? ""}';
    _log.info('EventService', 'connect() called: key=$key');
    disconnect(key);

    final conn = EventConnection(connType: connType, configId: configId, log: _log);
    _connections[key] = conn;
    return conn.connect();
  }

  void disconnect(String key) {
    final existing = _connections.remove(key);
    if (existing != null) {
      _log.info('EventService', 'disconnecting: key=$key');
      existing.dispose();
    }
  }

  void disconnectAll() {
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
  }
}
