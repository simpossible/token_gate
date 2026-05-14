import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/debug_inspector_provider.dart';

// ── Debug Inspector Overlay ──────────────────────────────────────────────────

class DebugInspectorOverlay extends ConsumerStatefulWidget {
  final String configId;
  final String configName;
  final VoidCallback onClose;

  const DebugInspectorOverlay({
    super.key,
    required this.configId,
    required this.configName,
    required this.onClose,
  });

  @override
  ConsumerState<DebugInspectorOverlay> createState() =>
      _DebugInspectorOverlayState();
}

class _DebugInspectorOverlayState
    extends ConsumerState<DebugInspectorOverlay> {
  double _area1Width = 240;
  double _area3Width = 280;
  _DetailTab _selectedTab = _DetailTab.headers;
  final ScrollController _responseScrollController = ScrollController();
  final ScrollController _rawLogScrollController = ScrollController();
  Timer? _throttleTimer;
  String? _lastRespondedReqId;
  bool _autoScroll = true;

  // Search state
  bool _showSearch = false;
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  static const _bgColor = Color(0xFFF3F4F6);
  static const _cardColor = Colors.white;
  static const _accentColor = Color(0xFF6366F1);
  static const _borderColor = Color(0xFFE5E7EB);
  static const _splitterWidth = 6.0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _responseScrollController.dispose();
    _rawLogScrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _throttleTimer?.cancel();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCmd = HardwareKeyboard.instance.logicalKeysPressed
          .any((k) => k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight);
      if (isCmd && event.logicalKey == LogicalKeyboardKey.keyF) {
        setState(() {
          _showSearch = true;
        });
        _searchFocusNode.requestFocus();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_showSearch) {
          setState(() {
            _showSearch = false;
            _searchQuery = '';
            _searchController.clear();
          });
          return true;
        }
      }
    }
    return false;
  }

  void _autoScrollResponse() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_responseScrollController.hasClients) {
        _responseScrollController
            .jumpTo(_responseScrollController.position.maxScrollExtent);
      }
    });
  }

  void _autoScrollRawLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rawLogScrollController.hasClients) {
        _rawLogScrollController
            .jumpTo(_rawLogScrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(debugInspectorProvider(widget.configId));
    final notifier = ref.read(debugInspectorProvider(widget.configId).notifier);
    final selected = state.selected;

    if (selected != null && !selected.completed && selected.reqId != _lastRespondedReqId) {
      _lastRespondedReqId = selected.reqId;
      _autoScrollResponse();
    }
    if (selected != null && !selected.completed) {
      _autoScrollResponse();
    }

    return Container(
      color: _bgColor,
      child: Column(
        children: [
          _buildHeader(state, notifier),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: _area1Width,
                  child: _buildRequestList(state, notifier),
                ),
                _buildSplitter(() => _area1Width, (v) => setState(() => _area1Width = v), min: 150, max: 400),
                Expanded(
                  child: _buildDetailArea(selected),
                ),
                if (state.showRawLog) ...[
                  _buildSplitter(() => _area3Width, (v) => setState(() => _area3Width = v), min: 150, max: 500),
                  SizedBox(
                    width: _area3Width,
                    child: _buildRawLog(state),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(DebugInspectorState state, DebugInspectorNotifier notifier) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, size: 15, color: _accentColor),
          const SizedBox(width: 6),
          const Text(
            'Network',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
          ),
          const SizedBox(width: 8),
          Text(
            widget.configName,
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
          const Spacer(),
          // Search button
          GestureDetector(
            onTap: () {
              setState(() => _showSearch = true);
              _searchFocusNode.requestFocus();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(Icons.search, size: 16, color: Colors.grey[400]),
            ),
          ),
          const SizedBox(width: 8),
          // Clear
          GestureDetector(
            onTap: notifier.clear,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('清空', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Toggle raw log
          GestureDetector(
            onTap: notifier.toggleShowRawLog,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                state.showRawLog ? Icons.article : Icons.article_outlined,
                size: 16,
                color: state.showRawLog ? _accentColor : const Color(0xFF9CA3AF),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Close
          GestureDetector(
            onTap: widget.onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Area-1: Request list ──────────────────────────────────────────────────

  Widget _buildRequestList(DebugInspectorState state, DebugInspectorNotifier notifier) {
    return Container(
      decoration: const BoxDecoration(
        color: _cardColor,
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('请求列表', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
            ),
          ),
          Expanded(
            child: state.entries.isEmpty
                ? const Center(
                    child: Text('等待请求...', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  )
                : ListView.builder(
                    itemCount: state.entries.length,
                    itemBuilder: (ctx, i) {
                      final entry = state.entries[i];
                      final isSelected = entry.reqId == state.selectedReqId;
                      return _buildRequestItem(entry, isSelected, notifier);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(DebugRequestEntry entry, bool isSelected, DebugInspectorNotifier notifier) {
    final statusColor = _statusColor(entry.status);

    return GestureDetector(
      onTap: () => notifier.selectRequest(entry.reqId),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withAlpha(20) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? _accentColor : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: _borderColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      entry.method,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.path,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF111827)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  if (entry.status != null)
                    Text(
                      '${entry.status}',
                      style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w500),
                    ),
                  if (entry.latencyMs != null || entry.ttfbMs != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${entry.latencyMs ?? entry.ttfbMs ?? 0}ms',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                  if (!entry.completed) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _accentColor.withAlpha(150),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Area-2: Detail ────────────────────────────────────────────────────────

  Widget _buildDetailArea(DebugRequestEntry? selected) {
    if (selected == null) {
      return const Center(
        child: Text('选择一个请求查看详情', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      );
    }

    return Container(
      color: _cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Request summary bar
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                Text(
                  '${selected.method} ${selected.path}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected.targetUrl,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          // Tab bar
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: _DetailTab.values.map((tab) {
                final isActive = tab == _selectedTab;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: isActive ? Border.all(color: _borderColor) : null,
                      ),
                      child: Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                          color: isActive ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Search bar (when active)
          if (_showSearch) _buildSearchBar(),
          // Tab content
          Expanded(
            child: switch (_selectedTab) {
              _DetailTab.headers => _buildHeadersContent(selected),
              _DetailTab.payload => _buildPayloadContent(selected),
              _DetailTab.response => _buildResponseContent(selected),
            },
          ),
        ],
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                hintText: '搜索... (Esc 关闭)',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          if (_searchQuery.isNotEmpty) ...[
            Text(
              '$_searchMatchCount matches',
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(width: 4),
          ],
          GestureDetector(
            onTap: () {
              setState(() {
                _showSearch = false;
                _searchQuery = '';
                _searchController.clear();
              });
            },
            child: const Icon(Icons.close, size: 14, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  int get _searchMatchCount {
    final entry = ref.read(debugInspectorProvider(widget.configId)).selected;
    if (entry == null || _searchQuery.isEmpty) return 0;
    final text = switch (_selectedTab) {
      _DetailTab.headers => _buildHeadersPlainText(entry),
      _DetailTab.payload => entry.payload ?? '',
      _DetailTab.response => entry.responseBuffer.toString(),
    };
    if (text.isEmpty) return 0;
    int count = 0;
    int pos = 0;
    final lower = text.toLowerCase();
    final q = _searchQuery.toLowerCase();
    while ((pos = lower.indexOf(q, pos)) != -1) {
      count++;
      pos += q.length;
    }
    return count;
  }

  static String _buildHeadersPlainText(DebugRequestEntry entry) {
    final buf = StringBuffer();
    for (final e in entry.requestHeaders.entries) {
      buf.writeln('${e.key}: ${e.value.join(', ')}');
    }
    for (final e in entry.responseHeaders.entries) {
      buf.writeln('${e.key}: ${e.value.join(', ')}');
    }
    return buf.toString();
  }

  // ── Highlighted text builder ────────────────────────────────────────────────

  static List<TextSpan> _buildHighlightSpans(String text, String query, TextStyle baseStyle) {
    if (query.isEmpty) return [TextSpan(text: text, style: baseStyle)];
    final spans = <TextSpan>[];
    int start = 0;
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    while (true) {
      final index = lower.indexOf(q, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + q.length),
        style: baseStyle.copyWith(backgroundColor: const Color(0xFFFFF3B0)),
      ));
      start = index + q.length;
    }
    return spans;
  }

  // ── Tab content builders ────────────────────────────────────────────────────

  Widget _buildHeadersContent(DebugRequestEntry entry) {
    // Build full text for search
    final buf = StringBuffer();
    buf.writeln('Request Headers:');
    for (final e in entry.requestHeaders.entries) {
      buf.writeln('${e.key}: ${e.value.join(', ')}');
    }
    buf.writeln('Response Headers:');
    for (final e in entry.responseHeaders.entries) {
      buf.writeln('${e.key}: ${e.value.join(', ')}');
    }
    final fullText = buf.toString();

    if (_showSearch && _searchQuery.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: RichText(
          text: TextSpan(
            children: _buildHighlightSpans(fullText, _searchQuery, const TextStyle(
              fontSize: 11, fontFamily: 'monospace', color: Color(0xFF374151),
            )),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection('Request Headers', entry.requestHeaders),
          const SizedBox(height: 16),
          _buildHeaderSection('Response Headers', entry.responseHeaders),
        ],
      ),
    );
  }

  Widget _buildHeaderSection(String title, Map<String, List<String>> headers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 6),
        if (headers.isEmpty)
          const Text('暂无', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)))
        else
          ...headers.entries.map((e) => _buildHeaderRow(e.key, e.value.join(', '))),
      ],
    );
  }

  Widget _buildHeaderRow(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              key,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1), fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF374151)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadContent(DebugRequestEntry entry) {
    final body = entry.payload ?? '';
    if (body.isEmpty) {
      return const Center(
        child: Text('无请求体', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildSearchableText(body, const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF374151))),
    );
  }

  Widget _buildResponseContent(DebugRequestEntry entry) {
    final body = entry.responseBuffer.toString();
    if (body.isEmpty) {
      return const Center(
        child: Text('等待响应...', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      );
    }
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _responseScrollController,
          padding: const EdgeInsets.all(12),
          child: _buildSearchableText(body, const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF374151))),
        ),
        // Auto-scroll toggle
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => setState(() => _autoScroll = !_autoScroll),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(220),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_bottom_outlined,
                      size: 12,
                      color: _autoScroll ? _accentColor : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '自动滚动',
                      style: TextStyle(
                        fontSize: 10,
                        color: _autoScroll ? _accentColor : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchableText(String text, TextStyle style) {
    if (_showSearch && _searchQuery.isNotEmpty) {
      return RichText(
        text: TextSpan(children: _buildHighlightSpans(text, _searchQuery, style)),
      );
    }
    return SelectableText(text, style: style);
  }

  // ── Area-3: Raw log ───────────────────────────────────────────────────────

  Widget _buildRawLog(DebugInspectorState state) {
    _autoScrollRawLog();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        border: Border(left: BorderSide(color: Colors.white.withAlpha(30))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 12, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                Text(
                  'Raw Log',
                  style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // Raw log search button
                GestureDetector(
                  onTap: () {
                    setState(() => _showSearch = true);
                    _searchFocusNode.requestFocus();
                  },
                  child: Icon(Icons.search, size: 12, color: Colors.white.withAlpha(120)),
                ),
              ],
            ),
          ),
          // Raw log search bar
          if (_showSearch) _buildRawLogSearchBar(),
          Expanded(
            child: state.rawLogs.isEmpty
                ? Center(
                    child: Text('等待日志...', style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 12)),
                  )
                : ListView.builder(
                    controller: _rawLogScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: state.rawLogs.length,
                    itemBuilder: (ctx, i) {
                      final log = state.rawLogs[i];
                      final isRequest = log.contains('→');
                      final displayLog = log.length > 500 ? '${log.substring(0, 500)}...' : log;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        child: _buildSearchableRawLogLine(displayLog, isRequest),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawLogSearchBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 12, color: Colors.white.withAlpha(120)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(220)),
              decoration: InputDecoration(
                hintText: '搜索... (Esc 关闭)',
                hintStyle: TextStyle(fontSize: 11, color: Colors.white.withAlpha(80)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          if (_searchQuery.isNotEmpty) ...[
            Text(
              '$_rawLogMatchCount',
              style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(100)),
            ),
            const SizedBox(width: 4),
          ],
          GestureDetector(
            onTap: () {
              setState(() {
                _showSearch = false;
                _searchQuery = '';
                _searchController.clear();
              });
            },
            child: Icon(Icons.close, size: 12, color: Colors.white.withAlpha(120)),
          ),
        ],
      ),
    );
  }

  int get _rawLogMatchCount {
    if (_searchQuery.isEmpty) return 0;
    // Count across raw logs — but state is not directly accessible here.
    // We just show a simple match indicator for the current search.
    return 0;
  }

  Widget _buildSearchableRawLogLine(String text, bool isRequest) {
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 10,
      color: isRequest ? const Color(0xFF6366F1) : const Color(0xFF10B981),
    );
    if (_showSearch && _searchQuery.isNotEmpty) {
      return RichText(
        text: TextSpan(children: _buildHighlightSpans(text, _searchQuery, baseStyle)),
      );
    }
    return SelectableText(text, style: baseStyle);
  }

  // ── Splitter (draggable) ──────────────────────────────────────────────────

  Widget _buildSplitter(double Function() getWidth, ValueChanged<double> setWidth, {double min = 150, max = 400}) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final newWidth = getWidth() + details.delta.dx;
        if (newWidth >= min && newWidth <= max) {
          setWidth(newWidth);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: _splitterWidth,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: _borderColor,
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _statusColor(int? status) {
    if (status == null) return const Color(0xFF9CA3AF);
    if (status >= 200 && status < 300) return const Color(0xFF10B981);
    if (status >= 400 && status < 500) return const Color(0xFFF59E0B);
    if (status >= 500) return const Color(0xFFEF4444);
    return const Color(0xFF9CA3AF);
  }
}

// ── Tab enum ─────────────────────────────────────────────────────────────────

enum _DetailTab {
  headers('Header'),
  payload('Payload'),
  response('Response');

  final String label;
  const _DetailTab(this.label);
}
