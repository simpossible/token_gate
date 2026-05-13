import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../models/agent.dart';
import '../models/token_config.dart';
import '../providers/providers.dart';
import '../providers/update_provider.dart';
import '../services/log_service.dart';
import 'config_detail.dart';
import 'config_form.dart';
import 'config_list.dart';
import 'log_panel.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> with WindowListener {
  // edit mode: null = no sheet open; non-null = config being edited (or sentinel for create)
  bool _showForm = false;
  TokenConfig? _editingConfig;
  bool _showLogPanel = false;
  String? _logPanelConfigId;
  String? _logPanelConfigName;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initTray();
    _startUpdateCheck();
  }

  void _startUpdateCheck() {
    checkForUpdate(ref);
    _updateCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      checkForUpdate(ref);
    });
  }

  Future<void> _initTray() async {
    try {
      await ref.read(trayServiceProvider).init();
    } catch (_) {
      // Tray might not be available on all platforms
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    windowManager.removeListener(this);
    ref.read(trayServiceProvider).dispose();
    super.dispose();
  }

  // Close → hide to tray
  @override
  void onWindowClose() {
    windowManager.hide();
  }

  void _openCreate() {
    setState(() {
      _editingConfig = null;
      _showForm = true;
    });
  }

  void _openEdit(TokenConfig config) {
    setState(() {
      _editingConfig = config;
      _showForm = true;
    });
  }

  void _closeForm() {
    setState(() => _showForm = false);
  }

  void _openLogDir() async {
    final log = ref.read(logServiceProvider);
    final dir = LogService.logDirPath;
    log.info('HomeView', 'opening log directory: $dir');
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      } else {
        await Process.run('explorer', [dir]);
      }
    } catch (e) {
      log.error('HomeView', 'failed to open log directory', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(agentsProvider);
    final selectedAgentType = ref.watch(selectedAgentTypeProvider);
    final selectedId = ref.watch(selectedConfigIdProvider);
    final configsAsync = ref.watch(configsProvider);

    // Pre-fetch companies so the data is ready when the form opens
    ref.watch(companiesProvider);

    // Auto-select: active config first, then first in list
    ref.listen(configsProvider, (prev, next) {
      final configs = next.valueOrNull;
      if (configs == null || configs.isEmpty) return;
      final current = ref.read(selectedConfigIdProvider);
      if (current != null && configs.any((c) => c.id == current)) return;
      final active = configs.where((c) => c.isActive).firstOrNull;
      ref.read(selectedConfigIdProvider.notifier).state =
          (active ?? configs.first).id;
    });

    // Resolve the currently selected config object
    final selectedConfig = configsAsync.valueOrNull
        ?.where((c) => c.id == selectedId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Stack(
          children: [
            // ── Main content ────────────────────────────────────────────────
            Column(
            children: [
              _TopBar(
                agentsAsync: agentsAsync,
                selectedAgentType: selectedAgentType,
                onAgentChanged: (type) {
                  ref.read(selectedAgentTypeProvider.notifier).state = type;
                  ref.read(selectedConfigIdProvider.notifier).state = null;
                  ref.read(configsProvider.notifier).reload();
                },
                onCreateTap: _openCreate,
                onOpenLogs: _openLogDir,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConfigList(onCreateTap: _openCreate),
                    Expanded(
                      child: selectedConfig != null
                          ? ConfigDetail(
                              config: selectedConfig,
                              onEdit: () => _openEdit(selectedConfig),
                              onDeleted: () {},
                              onShowLog: () {
                                setState(() {
                                  _showLogPanel = true;
                                  _logPanelConfigId = selectedConfig.id;
                                  _logPanelConfigName = selectedConfig.name;
                                });
                              },
                            )
                          : _EmptyDetail(onCreateTap: _openCreate),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Log panel overlay (right side)
          if (_showLogPanel && _logPanelConfigId != null)
            Positioned(
              top: 52,
              right: 0,
              bottom: 0,
              child: LogPanel(
                configId: _logPanelConfigId!,
                configName: _logPanelConfigName ?? '',
                eventService: ref.read(eventServiceProvider),
                logService: ref.read(logServiceProvider),
                onClose: () {
                  setState(() {
                    _showLogPanel = false;
                    _logPanelConfigId = null;
                    _logPanelConfigName = null;
                  });
                },
              ),
            ),

          // ── Modal overlay for create / edit ─────────────────────────────
          if (_showForm) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeForm,
              child: Container(color: Colors.black.withValues(alpha: 0.30)),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400, maxHeight: 490),
                child: ConfigForm(
                  config: _editingConfig,
                  onDone: _closeForm,
                ),
              ),
            ),
          ],
          ],
        ),
      ),
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final AsyncValue agentsAsync;
  final String selectedAgentType;
  final ValueChanged<String> onAgentChanged;
  final VoidCallback onCreateTap;
  final VoidCallback onOpenLogs;

  const _TopBar({
    required this.agentsAsync,
    required this.selectedAgentType,
    required this.onAgentChanged,
    required this.onCreateTap,
    required this.onOpenLogs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newVersion = ref.watch(newVersionProvider);
    return DragToMoveArea(
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.black.withAlpha(18)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Logo
            const Text(
              'TokenGate',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6366F1),
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),

            // New version indicator
            if (newVersion != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_upward, size: 14, color: Color(0xFF6366F1)),
                        SizedBox(width: 4),
                        Text(
                          '有新版本',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Agent type selector
            agentsAsync.when(
              loading: () => const SizedBox(width: 100),
              error: (e, st) => const SizedBox(width: 100),
              data: (agents) {
                final agentList = agents as List<Agent>;
                final selected = agentList.firstWhere(
                  (a) => a.type == selectedAgentType,
                  orElse: () => agentList.first,
                );
                return PopupMenuButton<String>(
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 4),
                  constraints: const BoxConstraints(minWidth: 120),
                  onSelected: onAgentChanged,
                  itemBuilder: (_) => agentList
                      .map((a) => PopupMenuItem<String>(
                            value: a.type,
                            height: 32,
                            child: Text(
                              a.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: a.type == selectedAgentType
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: const Color(0xFF374151),
                              ),
                            ),
                          ))
                      .toList(),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF374151),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 16, color: Color(0xFF9CA3AF)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),

            // More menu
            PopupMenuButton<String>(
              position: PopupMenuPosition.under,
              offset: const Offset(0, 4),
              onSelected: (value) {
                if (value == 'create') {
                  onCreateTap();
                } else if (value == 'logs') {
                  onOpenLogs();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem<String>(
                  value: 'create',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16, color: Color(0xFF374151)),
                      SizedBox(width: 8),
                      Text('创建配置', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'logs',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, size: 16, color: Color(0xFF374151)),
                      SizedBox(width: 8),
                      Text('查看日志', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
              child: Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.menu, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty detail state ────────────────────────────────────────────────────────

class _EmptyDetail extends StatelessWidget {
  final VoidCallback onCreateTap;

  const _EmptyDetail({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '选择左侧配置查看详情',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '或',
            style: TextStyle(color: Colors.grey[300], fontSize: 12),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('创建新配置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
