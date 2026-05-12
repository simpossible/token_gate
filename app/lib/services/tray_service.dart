import 'dart:async';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'event_service.dart';

class TrayService with TrayListener {
  final EventService _eventService;
  StreamSubscription? _subscription;
  int _deltaInput = 0;
  int _deltaOutput = 0;
  Timer? _clearTimer;

  TrayService(this._eventService);

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icons/tray_icon.png');
    await _buildMenu();

    // Subscribe to total_token_change events
    final stream = _eventService.connect('event');
    _subscription = stream.listen(_onEvent);
  }

  void _onEvent(EventMessage msg) {
    if (msg.type == 'total_token_change') {
      final payload = msg.data['payload'] as Map<String, dynamic>? ?? {};
      final addedIn = payload['added_in_tokens'] as int? ?? 0;
      final addedOut = payload['added_out_tokens'] as int? ?? 0;
      _deltaInput += addedIn;
      _deltaOutput += addedOut;
      _updateTitle();

      // Reset clear timer on each event
      _clearTimer?.cancel();
      _clearTimer = Timer(const Duration(seconds: 3), () {
        _deltaInput = 0;
        _deltaOutput = 0;
        _updateTitle();
      });
    }
  }

  Future<void> _updateTitle() async {
    if (_deltaInput > 0 || _deltaOutput > 0) {
      await trayManager.setTitle('↑${_fmt(_deltaInput)} ↓${_fmt(_deltaOutput)}');
    } else {
      await trayManager.setTitle('');
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
    _clearTimer?.cancel();
    _subscription?.cancel();
    _eventService.disconnect('event_');
    trayManager.removeListener(this);
  }
}
