import 'dart:async';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api_service.dart';
import 'event_service.dart';

class TrayService with TrayListener {
  final ApiService _api;
  final EventService _eventService;
  StreamSubscription? _subscription;
  int _totalInput = 0;
  int _totalOutput = 0;

  TrayService(this._api, this._eventService);

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icons/tray_icon.png');
    await _buildMenu();

    // Fetch initial totals
    try {
      final agents = await _api.listAgents();
      for (final agent in agents) {
        final id = agent.activeConfigId;
        if (id == null) continue;
        final stats = await _api.getUsageStats(id);
        _totalInput += stats.inputTokens;
        _totalOutput += stats.outputTokens;
      }
      _updateTitle();
    } catch (_) {}

    // Subscribe to total_token_change events
    final stream = _eventService.connect('event');
    _subscription = stream.listen(_onEvent);
  }

  void _onEvent(EventMessage msg) {
    if (msg.type == 'total_token_change') {
      final addedIn = msg.data['added_in_tokens'] as int? ?? 0;
      final addedOut = msg.data['added_out_tokens'] as int? ?? 0;
      _totalInput += addedIn;
      _totalOutput += addedOut;
      _updateTitle();
    }
  }

  Future<void> _updateTitle() async {
    if (_totalInput > 0 || _totalOutput > 0) {
      await trayManager.setTitle('↑${_fmt(_totalInput)} ↓${_fmt(_totalOutput)}');
    }
  }

  Future<void> _buildMenu() async {
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(key: 'open', label: '打开 TokenGate'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ],
    ));
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        windowManager.show();
        windowManager.focus();
      case 'quit':
        windowManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  void dispose() {
    _subscription?.cancel();
    _eventService.disconnect('event_');
    trayManager.removeListener(this);
  }
}
