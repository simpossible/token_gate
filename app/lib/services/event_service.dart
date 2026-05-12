import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const _base = 'http://127.0.0.1:12122';

class EventMessage {
  final String type;
  final Map<String, dynamic> data;

  EventMessage(this.type, this.data);
}

class EventConnection {
  final String connType;
  final String? configId;
  http.Client? _client;
  StreamSubscription? _subscription;
  StreamController<EventMessage>? _controller;
  Timer? _reconnectTimer;
  bool _disposed = false;

  EventConnection({required this.connType, this.configId});

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

    _client = http.Client();
    final request = http.Request('GET', Uri.parse(url));

    _client!.send(request).then((streamedResponse) {
      final stream = streamedResponse.stream;
      String buffer = '';
      String currentEvent = '';

      _subscription = stream.listen(
        (data) {
          buffer += utf8.decode(data, allowMalformed: true);
          final lines = buffer.split('\n');
          buffer = lines.removeLast(); // keep incomplete line

          for (final line in lines) {
            if (line.startsWith('event: ')) {
              currentEvent = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              final dataStr = line.substring(6);
              try {
                final json = jsonDecode(dataStr) as Map<String, dynamic>;
                if (currentEvent.isNotEmpty && _controller != null && !_controller!.isClosed) {
                  _controller!.add(EventMessage(currentEvent, json));
                }
              } catch (_) {}
              currentEvent = '';
            } else if (line.trim().isEmpty) {
              currentEvent = '';
            }
          }
        },
        onError: (e) {
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
      );
    }).catchError((e) {
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
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
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanup();
    _controller?.close();
  }
}

class EventService {
  final Map<String, EventConnection> _connections = {};

  Stream<EventMessage> connect(String connType, {String? configId}) {
    final key = '${connType}_${configId ?? ""}';
    disconnect(key);

    final conn = EventConnection(connType: connType, configId: configId);
    _connections[key] = conn;
    return conn.connect();
  }

  void disconnect(String key) {
    final existing = _connections.remove(key);
    existing?.dispose();
  }

  void disconnectAll() {
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
  }
}
