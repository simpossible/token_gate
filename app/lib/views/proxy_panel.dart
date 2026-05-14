import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy_config.dart';
import '../providers/providers.dart';

class ProxyPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const ProxyPanel({super.key, required this.onClose});

  @override
  ConsumerState<ProxyPanel> createState() => _ProxyPanelState();
}

class _ProxyPanelState extends ConsumerState<ProxyPanel> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _enabled = false;
  bool _saving = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController();
    _portController = TextEditingController();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _loadFromRemote(ProxyConfig config) {
    if (_initialized) return;
    _initialized = true;
    _hostController.text = config.host;
    _portController.text = config.port;
    _enabled = config.enabled;
  }

  Future<void> _save() async {
    final host = _hostController.text.trim().isNotEmpty
        ? _hostController.text.trim()
        : '127.0.0.1';
    final port = _portController.text.trim().isNotEmpty
        ? _portController.text.trim()
        : '7890';
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).setProxyConfig(
            ProxyConfig(host: host, port: port, enabled: _enabled),
          );
      ref.invalidate(proxyConfigProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('代理设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proxyAsync = ref.watch(proxyConfigProvider);

    return Container(
      color: Colors.white,
      child: proxyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (config) {
          _loadFromRemote(config);
          return _buildContent();
        },
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.black.withAlpha(12)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.vpn_lock, size: 16, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              const Text(
                '代理设置',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child:
                      Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Enable toggle card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_lock,
                          size: 20, color: Color(0xFF6366F1)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '启用代理',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF111827),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '所有代理请求将通过指定的代理服务器转发',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        activeThumbColor: const Color(0xFF6366F1),
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Host + Port card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '代理服务器地址',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '支持 HTTP/SOCKS5 代理',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _hostController,
                              enabled: _enabled,
                              decoration: InputDecoration(
                                hintText: '127.0.0.1',
                                hintStyle: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF9CA3AF),
                                ),
                                filled: true,
                                fillColor: _enabled
                                    ? const Color(0xFFF9FAFB)
                                    : const Color(0xFFF3F4F6),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: _enabled
                                    ? const Color(0xFF111827)
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _portController,
                              enabled: _enabled,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '7890',
                                hintStyle: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF9CA3AF),
                                ),
                                filled: true,
                                fillColor: _enabled
                                    ? const Color(0xFFF9FAFB)
                                    : const Color(0xFFF3F4F6),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: _enabled
                                    ? const Color(0xFF111827)
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFF6366F1).withAlpha(128),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '保存',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
