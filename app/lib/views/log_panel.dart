import 'dart:async';
import 'package:flutter/material.dart';

import '../services/event_service.dart';

class LogPanel extends StatefulWidget {
  final String configId;
  final String configName;
  final EventService eventService;
  final VoidCallback onClose;

  const LogPanel({
    super.key,
    required this.configId,
    required this.configName,
    required this.eventService,
    required this.onClose,
  });

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    debugPrint('[LogPanel] initState: configId=${widget.configId}, configName=${widget.configName}');
    final stream = widget.eventService.connect('log', configId: widget.configId);
    _subscription = stream.listen((msg) {
      debugPrint('[LogPanel] received event: type=${msg.type}, data=${msg.data}');
      _onEvent(msg);
    });
  }

  static const int _maxLineLen = 2000;

  void _onEvent(EventMessage msg) {
    if (msg.type == 'gate_log') {
      final payload = msg.data['payload'] as Map<String, dynamic>?;
      var message = payload?['message'] as String? ?? '';
      if (message.isEmpty) return;
      if (message.length > _maxLineLen) {
        message = '${message.substring(0, _maxLineLen)}... (${message.length} chars)';
      }
      debugPrint('[LogPanel] gate_log message: ${message.substring(0, message.length > 100 ? 100 : message.length)}');
      setState(() {
        _logs.add(message);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.eventService.disconnect('log_${widget.configId}');
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E).withValues(alpha: 0.95),
        border: Border(left: BorderSide(color: Colors.white.withAlpha(30))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(
                  'Gate Log',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.configName,
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(Icons.close, size: 16, color: Colors.white.withAlpha(150)),
                ),
              ],
            ),
          ),
          // Log list
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      '等待请求...',
                      style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final isRequest = log.contains('→');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        child: SelectableText(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isRequest
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF10B981),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
