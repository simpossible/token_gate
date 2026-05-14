import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/event_service.dart';
import 'providers.dart';

const _maxEntries = 200;
const _prefKeyShowRawLog = 'debug_inspector_show_raw_log';

// ── Data models ──────────────────────────────────────────────────────────────

enum DebugKind {
  requestStart('request_start'),
  requestHeaders('request_headers'),
  requestBody('request_body'),
  responseHeaders('response_headers'),
  responseChunk('response_chunk'),
  requestEnd('request_end');

  final String value;
  const DebugKind(this.value);

  static DebugKind? fromString(String v) =>
      DebugKind.values.where((e) => e.value == v).firstOrNull;
}

class DebugRequestEntry {
  final String reqId;
  final int startedAtMs;

  String method;
  String path;
  String targetUrl;
  String agentType;
  String model;
  int? status;
  bool completed;

  Map<String, List<String>> requestHeaders;
  Map<String, List<String>> responseHeaders;
  String? payload;
  final StringBuffer responseBuffer;
  int? latencyMs;
  int? ttfbMs;
  int? inputTokens;
  int? outputTokens;

  DebugRequestEntry({
    required this.reqId,
    required this.startedAtMs,
    this.method = '',
    this.path = '',
    this.targetUrl = '',
    this.agentType = '',
    this.model = '',
    this.status,
    this.completed = false,
    Map<String, List<String>>? requestHeaders,
    Map<String, List<String>>? responseHeaders,
    this.payload,
    StringBuffer? responseBuffer,
    this.latencyMs,
    this.ttfbMs,
    this.inputTokens,
    this.outputTokens,
  })  : requestHeaders = requestHeaders ?? {},
        responseHeaders = responseHeaders ?? {},
        responseBuffer = responseBuffer ?? StringBuffer();
}

// ── State ────────────────────────────────────────────────────────────────────

class DebugInspectorState {
  final List<DebugRequestEntry> entries;
  final String? selectedReqId;
  final List<String> rawLogs;
  final bool showRawLog;

  const DebugInspectorState({
    this.entries = const [],
    this.selectedReqId,
    this.rawLogs = const [],
    this.showRawLog = false,
  });

  DebugRequestEntry? get selected =>
      entries.where((e) => e.reqId == selectedReqId).firstOrNull;

  DebugInspectorState copyWith({
    List<DebugRequestEntry>? entries,
    String? selectedReqId,
    List<String>? rawLogs,
    bool? showRawLog,
  }) =>
      DebugInspectorState(
        entries: entries ?? this.entries,
        selectedReqId: selectedReqId ?? this.selectedReqId,
        rawLogs: rawLogs ?? this.rawLogs,
        showRawLog: showRawLog ?? this.showRawLog,
      );
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class DebugInspectorNotifier extends StateNotifier<DebugInspectorState> {
  final EventService _eventService;
  final String _configId;
  StreamSubscription? _subscription;
  final List<DebugRequestEntry> _entries = [];
  final List<String> _rawLogs = [];

  DebugInspectorNotifier(this._eventService, this._configId)
      : super(const DebugInspectorState()) {
    _init();
  }

  Future<void> _init() async {
    // Load persisted showRawLog preference
    final prefs = await SharedPreferences.getInstance();
    final showRawLog = prefs.getBool(_prefKeyShowRawLog) ?? true;
    state = state.copyWith(showRawLog: showRawLog);

    // Subscribe to SSE log stream
    final stream = _eventService.connect('log', configId: _configId);
    _subscription = stream.listen(_onEvent);
  }

  void _onEvent(EventMessage msg) {
    if (msg.type == 'gate_debug') {
      _handleDebugEvent(msg.data);
    } else if (msg.type == 'gate_log') {
      final payload = msg.data['payload'] as Map<String, dynamic>?;
      final message = payload?['message'] as String? ?? '';
      if (message.isNotEmpty) {
        _rawLogs.add(message);
        if (_rawLogs.length > 500) {
          _rawLogs.removeRange(0, _rawLogs.length - 500);
        }
        _notify();
      }
    }
  }

  void _handleDebugEvent(Map<String, dynamic> data) {
    final payload = data['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    final reqId = payload['req_id'] as String? ?? '';
    final kindStr = payload['kind'] as String? ?? '';
    final kind = DebugKind.fromString(kindStr);
    if (kind == null || reqId.isEmpty) return;

    switch (kind) {
      case DebugKind.requestStart:
        _upsert(reqId, (e) {
          e.method = payload['method'] as String? ?? '';
          e.path = payload['path'] as String? ?? '';
          e.targetUrl = payload['target_url'] as String? ?? '';
          e.agentType = payload['agent_type'] as String? ?? '';
          e.model = payload['model'] as String? ?? '';
        });
        break;
      case DebugKind.requestHeaders:
        _upsert(reqId, (e) {
          e.requestHeaders = _parseHeaders(payload['request_headers']);
        });
        break;
      case DebugKind.requestBody:
        _upsert(reqId, (e) {
          e.payload = payload['body'] as String? ?? '';
        });
        break;
      case DebugKind.responseHeaders:
        _upsert(reqId, (e) {
          e.status = payload['status'] as int?;
          e.responseHeaders = _parseHeaders(payload['response_headers']);
        });
        break;
      case DebugKind.responseChunk:
        _upsert(reqId, (e) {
          final chunk = payload['chunk'] as String? ?? '';
          e.responseBuffer.writeln(chunk);
        });
        break;
      case DebugKind.requestEnd:
        _upsert(reqId, (e) {
          e.completed = true;
          e.latencyMs = payload['latency_ms'] as int?;
          e.ttfbMs = payload['ttfb_ms'] as int?;
          final usage = payload['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            e.inputTokens = usage['input_tokens'] as int?;
            e.outputTokens = usage['output_tokens'] as int?;
          }
        });
        break;
    }
    _notify();
  }

  void _upsert(String reqId, void Function(DebugRequestEntry) update) {
    var entry = _entries.where((e) => e.reqId == reqId).firstOrNull;
    if (entry == null) {
      entry = DebugRequestEntry(reqId: reqId, startedAtMs: DateTime.now().millisecondsSinceEpoch);
      _entries.insert(0, entry);
      if (_entries.length > _maxEntries) {
        _entries.removeRange(_maxEntries, _entries.length);
      }
      // Auto-select first entry
      if (state.selectedReqId == null) {
        state = state.copyWith(selectedReqId: reqId);
      }
    }
    update(entry);
  }

  void _notify() {
    state = state.copyWith(
      entries: List.unmodifiable(_entries),
      rawLogs: List.unmodifiable(_rawLogs),
    );
  }

  void selectRequest(String reqId) {
    state = state.copyWith(selectedReqId: reqId);
  }

  void clear() {
    _entries.clear();
    _rawLogs.clear();
    state = DebugInspectorState(showRawLog: state.showRawLog);
  }

  Future<void> toggleShowRawLog() async {
    final next = !state.showRawLog;
    state = state.copyWith(showRawLog: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyShowRawLog, next);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _eventService.disconnect('log_$_configId');
    super.dispose();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final debugInspectorProvider = StateNotifierProvider.family<
    DebugInspectorNotifier, DebugInspectorState, String>(
  (ref, configId) {
    final eventService = ref.read(eventServiceProvider);
    return DebugInspectorNotifier(eventService, configId);
  },
);

// ── Helpers ──────────────────────────────────────────────────────────────────

Map<String, List<String>> _parseHeaders(dynamic raw) {
  if (raw is Map) {
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is List) {
        result[entry.key.toString()] = v.map((e) => e.toString()).toList();
      } else {
        result[entry.key.toString()] = [v.toString()];
      }
    }
    return result;
  }
  return {};
}
