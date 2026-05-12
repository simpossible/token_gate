import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../models/token_config.dart';
import '../providers/providers.dart';
import 'config_detail.dart';
import 'config_form.dart';
import 'config_list.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> with WindowListener {
  // edit mode: null = no sheet open; non-null = config being edited (or sentinel for create)
  bool _showForm = false;
  TokenConfig? _editingConfig;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initTray();
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

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(agentsProvider);
    final selectedAgentType = ref.watch(selectedAgentTypeProvider);
    final selectedId = ref.watch(selectedConfigIdProvider);
    final configsAsync = ref.watch(configsProvider);

    // Resolve the currently selected config object
    final selectedConfig = configsAsync.valueOrNull
        ?.where((c) => c.id == selectedId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
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
                            )
                          : _EmptyDetail(onCreateTap: _openCreate),
                    ),
                  ],
                ),
              ),
            ],
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
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final AsyncValue agentsAsync;
  final String selectedAgentType;
  final ValueChanged<String> onAgentChanged;
  final VoidCallback onCreateTap;

  const _TopBar({
    required this.agentsAsync,
    required this.selectedAgentType,
    required this.onAgentChanged,
    required this.onCreateTap,
  });

  @override
  Widget build(BuildContext context) {
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

            // Agent type selector
            agentsAsync.when(
              loading: () => const SizedBox(width: 140),
              error: (e, st) => const SizedBox(width: 140),
              data: (agents) {
                final agentList = agents as List;
                return Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedAgentType,
                      icon: const Icon(Icons.expand_more, size: 16),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF374151),
                      ),
                      items: agentList
                          .map((a) => DropdownMenuItem<String>(
                                value: a.type as String,
                                child: Text(a.label as String),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onAgentChanged(v);
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),

            // Create button
            SizedBox(
              height: 32,
              width: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.add, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onCreateTap,
                tooltip: '创建配置',
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
