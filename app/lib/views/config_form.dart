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
  String? _selectedCompanyName;
  String? _namePlaceholder;
  List<String> _modelOptions = [];
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
    _selectedAgentType = c?.agentType ?? ref.read(selectedAgentTypeProvider);
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
    final companiesAsync = ref.watch(companiesProvider);

    // In edit mode, auto-match vendor from config URL once companies are loaded
    if (_isEdit && _selectedCompanyName == null) {
      final companies = companiesAsync.valueOrNull;
      if (companies != null && companies.isNotEmpty) {
        final match = companies.where((c) => c.url == widget.config!.url).firstOrNull;
        if (match != null) {
          _selectedCompanyName = match.name;
          _modelOptions = match.models;
        }
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  _isEdit ? '编辑配置' : '创建配置',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                    onPressed: widget.onDone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // ── Form fields ──────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _Field(
                        label: '名称',
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: _deco(_namePlaceholder ?? '配置名称'),
                          style: _fieldTextStyle,
                          validator: (v) =>
                              (v == null || v.isEmpty) && _namePlaceholder == null
                                  ? '请输入名称'
                                  : null,
                        ),
                      ),

                      _Field(
                        label: 'API Key',
                        child: TextFormField(
                          controller: _apiKeyCtrl,
                          decoration: _deco('sk-ant-...'),
                          style: _fieldTextStyle,

                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入 API Key' : null,
                        ),
                      ),

                      // Vendor preset
                      _Field(
                        label: '厂商（可选）',
                        child: LayoutBuilder(
                          builder: (ctx, bc) {
                            final companies =
                                companiesAsync.valueOrNull ?? [];
                            return PopupMenuButton<String>(
                              enabled: companies.isNotEmpty,
                              position: PopupMenuPosition.under,
                              constraints: BoxConstraints(
                                minWidth: bc.maxWidth,
                                maxWidth: bc.maxWidth,
                                maxHeight: 200,
                              ),
                              onSelected: (url) {
                                final company = companies
                                    .firstWhere((c) => c.url == url);
                                _urlCtrl.text = url;
                                setState(() {
                                  _selectedCompanyName = company.name;
                                  _namePlaceholder = _buildNamePlaceholder(company.name);
                                  if (company.models.isNotEmpty) {
                                    _modelOptions = company.models;
                                    _modelCtrl.text = company.models.first;
                                  }
                                });
                              },
                              itemBuilder: (context) => companies
                                  .map((c) => PopupMenuItem<String>(
                                        value: c.url,
                                        height: 32,
                                        child: Text(c.name,
                                            style: const TextStyle(
                                                fontSize: 12)),
                                      ))
                                  .toList(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: const Color(0xFFE5E7EB)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _selectedCompanyName ??
                                            '选择厂商预设',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _selectedCompanyName != null
                                              ? const Color(0xFF111827)
                                              : const Color(0xFFD1D5DB),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down,
                                        size: 18,
                                        color: Color(0xFF9CA3AF)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      _Field(
                        label: 'API URL',
                        child: TextFormField(
                          controller: _urlCtrl,
                          decoration: _deco('https://api.anthropic.com'),
                          style: _fieldTextStyle,
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入 API URL' : null,
                        ),
                      ),

                      _Field(
                        label: '模型',
                        child: TextFormField(
                          controller: _modelCtrl,
                          decoration: _deco('claude-sonnet-4-5-20251022').copyWith(
                            suffixIcon: _modelOptions.isNotEmpty
                                ? PopupMenuButton<String>(
                                    tooltip: '选择模型',
                                    icon: const Icon(
                                      Icons.arrow_drop_down,
                                      size: 18,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                    onSelected: (value) =>
                                        _modelCtrl.text = value,
                                    itemBuilder: (context) => _modelOptions
                                        .map((m) => PopupMenuItem<String>(
                                              value: m,
                                              height: 32,
                                              child: Text(m,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                            ))
                                        .toList(),
                                  )
                                : null,
                          ),
                          style: _fieldTextStyle,
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入模型名称' : null,
                        ),
                      ),

                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12),
                          ),
                        ),

                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 14,
                                  width: 14,
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

  static const _fieldTextStyle = TextStyle(fontSize: 13, color: Color(0xFF111827));

  static String _buildNamePlaceholder(String companyName) {
    final now = DateTime.now();
    final ts = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    return '${companyName.replaceAll(RegExp(r'\s+'), '')}$ts';
  }

  InputDecoration _deco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF6366F1)),
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
        'name': _nameCtrl.text.isEmpty ? (_namePlaceholder ?? '') : _nameCtrl.text,
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

class _Field extends StatelessWidget {
  final String label;
  final Widget child;

  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
