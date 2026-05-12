import 'dart:async';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api_service.dart';

class TrayService with TrayListener {
  final ApiService _api;
  Timer? _timer;
  int _lastTs = DateTime.now().millisecondsSinceEpoch;

  TrayService(this._api);

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icons/tray_icon.png');
    await _buildMenu();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshTitle());
  }

  Future<void> _refreshTitle() async {
    try {
      final agents = await _api.listAgents();
      int input = 0;
      int output = 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final agent in agents) {
        final id = agent.activeConfigId;
        if (id == null) continue;
        final entries = await _api.getUsageDelta(id, _lastTs);
        for (final e in entries) {
          input += e.inputTokens;
          output += e.outputTokens;
        }
      }

      _lastTs = now;
      if (input > 0 || output > 0) {
        await trayManager.setTitle('↑${_fmt(input)} ↓${_fmt(output)}');
      }
    } catch (_) {
      // daemon may be unavailable
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
    _timer?.cancel();
    trayManager.removeListener(this);
  }
}
