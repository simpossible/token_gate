import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/latency_entry.dart';
import '../models/token_config.dart';
import '../models/usage_entry.dart';
import '../models/usage_stats.dart';
import '../providers/providers.dart';

class ConfigDetail extends ConsumerStatefulWidget {
  final TokenConfig config;
  final VoidCallback onEdit;
  final VoidCallback onDeleted;

  const ConfigDetail({
    super.key,
    required this.config,
    required this.onEdit,
    required this.onDeleted,
  });

  @override
  ConsumerState<ConfigDetail> createState() => _ConfigDetailState();
}

class _ConfigDetailState extends ConsumerState<ConfigDetail> {
  bool _showLineChart = true;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final statsAsync = ref.watch(usageStatsProvider(config.id));
    final usagesAsync = ref.watch(usagesProvider(config.id));
    final latencyAsync = ref.watch(latencyProvider(config.id));
    final companies = ref.watch(companiesProvider).valueOrNull ?? [];

    String vendorLabel;
    try {
      vendorLabel =
          companies.firstWhere((c) => c.url == config.url).name;
    } catch (_) {
      vendorLabel = config.url;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: name + action buttons
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      config.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (config.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '生效中',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: '编辑',
                onPressed: widget.onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                tooltip: '删除',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2.2.1 Basic info
          _InfoGrid(config: config, vendorLabel: vendorLabel),
          const SizedBox(height: 20),

          // 2.2.2 Stats
          statsAsync.when(
            loading: () => const _StatsRow(stats: UsageStats.empty),
            error: (e, st) => const _StatsRow(stats: UsageStats.empty),
            data: (stats) => _StatsRow(stats: stats),
          ),
          const SizedBox(height: 20),

          // 2.2.3 Token chart
          Row(
            children: [
              const Text(
                'Token 用量',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const Spacer(),
              _ChartToggle(
                isLine: _showLineChart,
                onToggle: (v) => setState(() => _showLineChart = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: usagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e', style: const TextStyle(fontSize: 12))),
              data: (entries) => _TokenChart(
                entries: entries,
                isLine: _showLineChart,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2.2.4 Latency chart
          const Text(
            '请求延迟',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: latencyAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e', style: const TextStyle(fontSize: 12))),
              data: (entries) => _LatencyChart(entries: entries),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定要删除"${widget.config.name}"？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(configsProvider.notifier).delete(widget.config.id);
      widget.onDeleted();
    }
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _InfoGrid extends StatelessWidget {
  final TokenConfig config;
  final String vendorLabel;

  const _InfoGrid({required this.config, required this.vendorLabel});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('ID', '${config.id}'),
      ('Agent 类型', config.agentType),
      ('厂商', vendorLabel),
      ('API Key', config.apiKey),
      ('模型', config.model),
      ('创建时间', _formatDate(config.createdAt)),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: items
          .map((e) => _InfoChip(label: e.$1, value: e.$2))
          .toList(),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    } catch (_) {
      return raw;
    }
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final UsageStats stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('请求数', '${stats.requests}'),
      ('输入 Tokens', _fmt(stats.inputTokens)),
      ('输出 Tokens', _fmt(stats.outputTokens)),
      ('平均延迟', '${stats.avgLatencyMs.toStringAsFixed(0)} ms'),
    ];

    return Row(
      children: items
          .map((e) => Expanded(child: _StatCard(label: e.$1, value: e.$2)))
          .toList(),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withAlpha(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _ChartToggle extends StatelessWidget {
  final bool isLine;
  final ValueChanged<bool> onToggle;

  const _ChartToggle({required this.isLine, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ToggleBtn(
          icon: Icons.show_chart,
          active: isLine,
          onTap: () => onToggle(true),
          tooltip: '折线图',
        ),
        const SizedBox(width: 4),
        _ToggleBtn(
          icon: Icons.bar_chart,
          active: !isLine,
          onTap: () => onToggle(false),
          tooltip: '柱状图',
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  const _ToggleBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6366F1) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active ? Colors.white : Colors.grey[500],
          ),
        ),
      ),
    );
  }
}

// ── Charts ───────────────────────────────────────────────────────────────────

class _TokenChart extends StatelessWidget {
  final List<UsageEntry> entries;
  final bool isLine;

  const _TokenChart({required this.entries, required this.isLine});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('暂无数据', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    // Take last 20 points
    final data = entries.length > 20 ? entries.sublist(entries.length - 20) : entries;

    if (isLine) {
      return LineChart(_buildLineData(data));
    } else {
      return BarChart(_buildBarData(data));
    }
  }

  LineChartData _buildLineData(List<UsageEntry> data) {
    List<FlSpot> inputSpots = [];
    List<FlSpot> outputSpots = [];
    List<FlSpot> totalSpots = [];

    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      inputSpots.add(FlSpot(i.toDouble(), e.inputTokens.toDouble()));
      outputSpots.add(FlSpot(i.toDouble(), e.outputTokens.toDouble()));
      totalSpots.add(
          FlSpot(i.toDouble(), (e.inputTokens + e.outputTokens).toDouble()));
    }

    return LineChartData(
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: null,
        getDrawingHorizontalLine: (_) => FlLine(
          color: Colors.black.withAlpha(15),
          strokeWidth: 1,
        ),
      ),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        _lineBar(inputSpots, const Color(0xFF6366F1)),
        _lineBar(outputSpots, const Color(0xFF10B981)),
        _lineBar(totalSpots, const Color(0xFFF59E0B)),
      ],
    );
  }

  LineChartBarData _lineBar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withAlpha(20),
      ),
    );
  }

  BarChartData _buildBarData(List<UsageEntry> data) {
    return BarChartData(
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: Colors.black.withAlpha(15),
          strokeWidth: 1,
        ),
      ),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      barGroups: List.generate(
        data.length,
        (i) => BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (data[i].inputTokens + data[i].outputTokens).toDouble(),
              color: const Color(0xFF6366F1),
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatencyChart extends StatelessWidget {
  final List<LatencyEntry> entries;

  const _LatencyChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('暂无数据', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    final data = entries.length > 30 ? entries.sublist(entries.length - 30) : entries;
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].ttfbMs.toDouble()),
    );

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawHorizontalLine: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.black.withAlpha(15),
            strokeWidth: 1,
          ),
        ),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFFF59E0B),
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFFF59E0B).withAlpha(25),
            ),
          ),
        ],
      ),
    );
  }
}
