import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
            data: (stats) {
              final usages = usagesAsync.valueOrNull ?? [];
              final avgLatencyMs = usages.isEmpty
                  ? 0
                  : (usages.map((e) => e.latencyMs).reduce((a, b) => a + b) /
                          usages.length)
                      .round();
              return _StatsRow(
                  stats: stats.copyWith(avgLatencyMs: avgLatencyMs));
            },
          ),
          const SizedBox(height: 20),

          // 2.2.3 Token chart card
          _ChartCard(
            title: 'Token 用量',
            trailing: _SegmentedPill(
              isLine: _showLineChart,
              onToggle: (v) => setState(() => _showLineChart = v),
            ),
            legend: _showLineChart
                ? const Row(children: [
                    _LegendDot(color: Color(0xFF6366F1), label: '输入'),
                    SizedBox(width: 12),
                    _LegendDot(color: Color(0xFF10B981), label: '输出'),
                    SizedBox(width: 12),
                    _LegendDot(color: Color(0xFFF59E0B), label: '合计'),
                  ])
                : const Row(children: [
                    _LegendDot(color: Color(0xFF6366F1), label: '合计'),
                  ]),
            child: usagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e', style: const TextStyle(fontSize: 12))),
              data: (entries) => _TokenChart(entries: entries, isLine: _showLineChart),
            ),
          ),
          const SizedBox(height: 12),

          // 2.2.4 Latency chart card
          _ChartCard(
            title: '请求延迟 TTFB',
            legend: const Row(children: [
              _LegendDot(color: Color(0xFFF59E0B), label: '延迟 (ms)'),
            ]),
            child: usagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('$e', style: const TextStyle(fontSize: 12))),
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
      ('ID', config.id),
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
      ('平均时延', _fmtLatency(stats.avgLatencyMs)),
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

  String _fmtLatency(int ms) {
    if (ms <= 0) return '-';
    return '${ms}ms';
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

// ── Chart card container ─────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget? legend;
  final Widget child;

  const _ChartCard({
    required this.title,
    this.trailing,
    this.legend,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          if (legend != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: legend!,
            ),
          SizedBox(
            height: 148,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Segmented pill toggle ─────────────────────────────────────────────────────

class _SegmentedPill extends StatelessWidget {
  final bool isLine;
  final ValueChanged<bool> onToggle;

  const _SegmentedPill({required this.isLine, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillTab(label: '折线', active: isLine, onTap: () => onToggle(true)),
          _PillTab(label: '柱状', active: !isLine, onTap: () => onToggle(false)),
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withAlpha(18), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? const Color(0xFF111827) : Colors.grey[500],
          ),
        ),
      ),
    );
  }
}

// ── Legend dot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

// ── Charts ───────────────────────────────────────────────────────────────────

String _fmtK(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

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
      totalSpots.add(FlSpot(i.toDouble(), (e.inputTokens + e.outputTokens).toDouble()));
    }

    const seriesNames = ['输入', '输出', '合计'];
    const seriesColors = [Color(0xFF6366F1), Color(0xFF10B981), Color(0xFFF59E0B)];

    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          tooltipRoundedRadius: 8,
          tooltipBorder: const BorderSide(color: Color(0xFFE5E7EB)),
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.barIndex;
            return LineTooltipItem(
              '${seriesNames[idx]}: ${_fmtK(s.y.toInt())}',
              TextStyle(
                color: seriesColors[idx],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
      ),
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: null,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.black.withAlpha(15), strokeWidth: 1),
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
      belowBarData: BarAreaData(show: true, color: color.withAlpha(20)),
    );
  }

  BarChartData _buildBarData(List<UsageEntry> data) {
    return BarChartData(
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          tooltipRoundedRadius: 8,
          tooltipBorder: const BorderSide(color: Color(0xFFE5E7EB)),
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
            '合计: ${_fmtK(rod.toY.toInt())}',
            const TextStyle(color: Color(0xFF6366F1), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.black.withAlpha(15), strokeWidth: 1),
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
  final List<UsageEntry> entries;

  const _LatencyChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final withLatency = entries.where((e) => e.latencyMs > 0).toList();
    if (withLatency.isEmpty) {
      return const Center(
        child: Text('暂无数据', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    final data = withLatency.length > 30 ? withLatency.sublist(withLatency.length - 30) : withLatency;
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].latencyMs.toDouble()),
    );

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipRoundedRadius: 8,
            tooltipBorder: const BorderSide(color: Color(0xFFE5E7EB)),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '${s.y.toInt()} ms',
              const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w600),
            )).toList(),
          ),
        ),
        gridData: FlGridData(
          drawHorizontalLine: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.black.withAlpha(15), strokeWidth: 1),
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
            belowBarData: BarAreaData(show: true, color: const Color(0xFFF59E0B).withAlpha(25)),
          ),
        ],
      ),
    );
  }
}
