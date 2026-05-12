import 'dart:async';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api_service.dart';

class TrayService with TrayListener {
  final ApiService _api;
  Timer? _timer;

  TrayService(this._api);

  Future<void> init() async {
    trayManager.addListener(this);

    await trayManager.setIcon(
      'assets/icons/tray_icon.png',
    );
    await _buildMenu();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshTitle(),
    );
  }

  Future<void> _refreshTitle() async {
    try {
      final delta = await _api.getUsageDelta();
      final up = _formatTokens(delta.inputTokens);
      final down = _formatTokens(delta.outputTokens);
      await trayManager.setTitle('↑$up ↓$down');
    } catch (_) {
      // daemon may be unavailable, ignore
    }
  }

  Future<void> _buildMenu() async {
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(
          key: 'open',
          label: '打开 TokenGate',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: '退出',
        ),
      ],
    ));
  }

  String _formatTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
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
