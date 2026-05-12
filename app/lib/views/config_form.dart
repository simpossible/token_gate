import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token_config.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';

class ConfigForm extends ConsumerStatefulWidget {
  // null = create mode; non-null = edit mode
  final TokenConfig? config;
  final VoidCallback onDone;

  const ConfigForm({super.key, this.config, required this.onDone});

  @override
  ConsumerState<ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<ConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _modelCtrl;
  String? _selectedAgentType;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.config != null;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _apiKeyCtrl = TextEditingController(text: c?.apiKey ?? '');
    _urlCtrl = TextEditingController(text: c?.url ?? '');
    _modelCtrl = TextEditingController(text: c?.model ?? '');
    _selectedAgentType =
        c?.agentType ?? ref.read(selectedAgentTypeProvider);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiKeyCtrl.dispose();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(agentsProvider);
    final companiesAsync = ref.watch(companiesProvider);

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _isEdit ? '编辑配置' : '创建配置',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onDone,
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Agent type (only on create)
                      if (!_isEdit)
                        agentsAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, st) => const SizedBox.shrink(),
                          data: (agents) => _FormField(
                            label: 'Agent 类型',
                            child: DropdownButtonFormField<String>(
                            initialValue: _selectedAgentType,
                              decoration: _inputDeco('选择 Agent 类型'),
                              items: agents
                                  .map((a) => DropdownMenuItem(
                                        value: a.type,
                                        child: Text(a.label),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedAgentType = v),
                              validator: (v) =>
                                  v == null ? '请选择 Agent 类型' : null,
                            ),
                          ),
                        ),

                      _FormField(
                        label: '名称',
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: _inputDeco('配置名称'),
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入名称' : null,
                        ),
                      ),

                      _FormField(
                        label: 'API Key',
                        child: TextFormField(
                          controller: _apiKeyCtrl,
                          decoration: _inputDeco('sk-ant-...'),
                          obscureText: true,
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入 API Key' : null,
                        ),
                      ),

                      // Vendor preset selector
                      companiesAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (e, st) => const SizedBox.shrink(),
                        data: (companies) => _FormField(
                          label: '厂商（可选）',
                          child: DropdownButtonFormField<String>(
                            initialValue: null,
                            decoration: _inputDeco('选择厂商预设（自动填充 URL 和模型）'),
                            items: companies
                                .map((c) => DropdownMenuItem(
                                      value: c.url,
                                      child: Text(c.name),
                                    ))
                                .toList(),
                            onChanged: (url) {
                              if (url == null) return;
                              final company = companies.firstWhere(
                                  (c) => c.url == url);
                              _urlCtrl.text = url;
                              if (company.models.isNotEmpty) {
                                _modelCtrl.text = company.models.first;
                              }
                            },
                          ),
                        ),
                      ),

                      _FormField(
                        label: 'API URL',
                        child: TextFormField(
                          controller: _urlCtrl,
                          decoration:
                              _inputDeco('https://api.anthropic.com'),
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入 API URL' : null,
                        ),
                      ),

                      _FormField(
                        label: '模型',
                        child: TextFormField(
                          controller: _modelCtrl,
                          decoration:
                              _inputDeco('claude-sonnet-4-5-20251022'),
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入模型名称' : null,
                        ),
                      ),

                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13),
                          ),
                        ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isEdit ? '保存' : '创建'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final body = {
        'name': _nameCtrl.text,
        'api_key': _apiKeyCtrl.text,
        'url': _urlCtrl.text,
        'model': _modelCtrl.text,
        if (!_isEdit) 'agent_type': _selectedAgentType,
      };
      if (_isEdit) {
        await api.updateConfig(widget.config!.id, body);
      } else {
        await api.createConfig(body);
      }
      await ref.read(configsProvider.notifier).reload();
      widget.onDone();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;

  const _FormField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
