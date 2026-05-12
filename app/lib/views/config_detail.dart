import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/token_config.dart';
import '../models/usage_entry.dart';
import '../models/usage_stats.dart';
import '../providers/providers.dart';

enum _TimeRange { today, sevenDays }

// Unified data point used by both charts (raw or hourly-aggregated).
class _ChartEntry {
  final int tsMs;
  final int inputTokens;
  final int outputTokens;
  final int latencyMs; // avg when aggregated, raw when today

  const _ChartEntry({
    required this.tsMs,
    required this.inputTokens,
    required this.outputTokens,
    required this.latencyMs,
  });

  DateTime get dt => DateTime.fromMillisecondsSinceEpoch(tsMs);
}

// Converts raw UsageEntry list into chart-ready _ChartEntry list.
// today  → filter to today's entries, show raw (no cap)
// 7days  → group by hour, sum tokens, avg latency
List<_ChartEntry> _buildChartEntries(
    List<UsageEntry> entries, _TimeRange range) {
  if (range == _TimeRange.today) {
    final now = DateTime.now();
    return entries
        .where((e) {
          final dt = e.createdAt;
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day;
        })
        .map((e) => _ChartEntry(
              tsMs: e.createdAtTs,
              inputTokens: e.inputTokens,
              outputTokens: e.outputTokens,
              latencyMs: e.latencyMs,
            ))
        .toList();
  }

  // 7-day hourly aggregation
  final Map<int, List<UsageEntry>> buckets = {};
  for (final e in entries) {
    final dt = e.createdAt;
    final key = DateTime(dt.year, dt.month, dt.day, dt.hour)
        .millisecondsSinceEpoch;
    buckets.putIfAbsent(key, () => []).add(e);
  }
  final keys = buckets.keys.toList()..sort();
  return keys.map((k) {
    final group = buckets[k]!;
    final totalIn = group.fold(0, (s, e) => s + e.inputTokens);
    final totalOut = group.fold(0, (s, e) => s + e.outputTokens);
    final withLat = group.where((e) => e.latencyMs > 0).toList();
    final avgLat = withLat.isEmpty
        ? 0
        : withLat.fold(0, (s, e) => s + e.latencyMs) ~/ withLat.length;
    return _ChartEntry(
      tsMs: k,
      inputTokens: totalIn,
      outputTokens: totalOut,
      latencyMs: avgLat,
    );
  }).toList();
}

class ConfigDetail extends ConsumerStatefulWidget {
  final TokenConfig config;
  final VoidCallback onEdit;
  final VoidCallback onDeleted;
  final VoidCallback? onShowLog;

  const ConfigDetail({
    super.key,
    required this.config,
    required this.onEdit,
    required this.onDeleted,
    this.onShowLog,
  });

  @override
  ConsumerState<ConfigDetail> createState() => _ConfigDetailState();
}

class _ConfigDetailState extends ConsumerState<ConfigDetail> {
  bool _showLineChart = true;
  _TimeRange _timeRange = _TimeRange.today;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeEvents();
  }

  void _subscribeEvents() {
    final eventService = ref.read(eventServiceProvider);
    final configId = widget.config.id;
    debugPrint('[ConfigDetail] subscribing events: configId=$configId');
    final stream = eventService.connect('event', configId: configId);
    _eventSubscription = stream.listen((msg) {
      debugPrint('[ConfigDetail] event received: type=${msg.type}, data=${msg.data}');
      if (msg.type == 'usage_new') {
        ref.invalidate(usageStatsProvider(configId));
        ref.invalidate(usagesProvider(configId));
      }
    });
  }

  @override
  void dispose() {
    debugPrint('[ConfigDetail] dispose: configId=${widget.config.id}');
    _eventSubscription?.cancel();
    final configId = widget.config.id;
    ref.read(eventServiceProvider).disconnect('event_$configId');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final statsAsync = ref.watch(usageStatsProvider(config.id));
    final usagesAsync = ref.watch(usagesProvider(config.id));
    final companies = ref.watch(companiesProvider).valueOrNull ?? [];

    String vendorLabel;
    try {
      vendorLabel = companies.firstWhere((c) => c.url == config.url).name;
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
              if (widget.onShowLog != null)
                IconButton(
                  icon: const Icon(Icons.terminal, size: 18),
                  tooltip: '实时日志',
                  onPressed: widget.onShowLog,
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.red),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RangePill(
                  range: _timeRange,
                  onToggle: (r) => setState(() => _timeRange = r),
                ),
                const SizedBox(width: 8),
                _SegmentedPill(
                  isLine: _showLineChart,
                  onToggle: (v) => setState(() => _showLineChart = v),
                ),
              ],
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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('$e',
                      style: const TextStyle(fontSize: 12))),
              data: (entries) {
                final data = _buildChartEntries(entries, _timeRange);
                return _TokenChart(entries: data, isLine: _showLineChart);
              },
            ),
          ),
          const SizedBox(height: 12),

          // 2.2.4 Latency chart card (shares same time range)
          _ChartCard(
            title: _timeRange == _TimeRange.today
                ? '请求延迟 TTFB'
                : '请求延迟 TTFB（小时均值）',
            legend: const Row(children: [
              _LegendDot(color: Color(0xFFF59E0B), label: '延迟 (ms)'),
            ]),
            child: usagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                  child: Text('$e',
                      style: const TextStyle(fontSize: 12))),
              data: (entries) {
                final data = _buildChartEntries(entries, _timeRange);
                return _LatencyChart(entries: data);
              },
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
      ('厂商', vendorLabel, false),
      ('API Key', config.apiKey, true),
      ('模型', config.model, false),
      ('创建时间', _formatDate(config.createdAt), false),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: items
          .map((e) => _InfoChip(label: e.$1, value: e.$2, copyable: e.$3))
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

class _InfoChip extends StatefulWidget {
  final String label;
  final String value;
  final bool copyable;

  const _InfoChip({required this.label, required this.value, this.copyable = false});

  @override
  State<_InfoChip> createState() => _InfoChipState();
}

class _InfoChipState extends State<_InfoChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.label}: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            _copied ? '已复制' : widget.value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _copied ? const Color(0xFF10B981) : const Color(0xFF111827),
            ),
          ),
          if (widget.copyable) ...[
            const SizedBox(width: 4),
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 13,
              color: _copied
                  ? const Color(0xFF10B981)
                  : Colors.grey[400],
            ),
          ],
        ],
      ),
    );

    if (!widget.copyable) return child;
    return GestureDetector(
      onTap: _copy,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: child,
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
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
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
            height: 172,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 8, 4),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Range pill toggle (今天 / 7天) ────────────────────────────────────────────

class _RangePill extends StatelessWidget {
  final _TimeRange range;
  final ValueChanged<_TimeRange> onToggle;

  const _RangePill({required this.range, required this.onToggle});

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
          _PillTab(
            label: '今天',
            active: range == _TimeRange.today,
            onTap: () => onToggle(_TimeRange.today),
          ),
          _PillTab(
            label: '7天',
            active: range == _TimeRange.sevenDays,
            onTap: () => onToggle(_TimeRange.sevenDays),
          ),
        ],
      ),
    );
  }
}

// ── Segmented pill toggle (折线 / 柱状) ────────────────────────────────────────

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
          _PillTab(
              label: '折线', active: isLine, onTap: () => onToggle(true)),
          _PillTab(
              label: '柱状', active: !isLine, onTap: () => onToggle(false)),
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: Colors.black.withAlpha(18),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
                active ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? const Color(0xFF111827)
                : Colors.grey[500],
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
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

// ── Shared chart helpers ──────────────────────────────────────────────────────

String _fmtTooltipTime(int tsMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$mo-$d $h:$m';
}

String _fmtK(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

// Rounds up to next "nice" number (1/2/5 × 10^n) with 20% headroom.
double _calcMaxY(double rawMax) {
  if (rawMax <= 0) return 100;
  final padded = rawMax * 1.2;
  double mag = 1;
  while (mag * 10 < padded) {
    mag *= 10;
  }
  if (padded <= mag) return mag;
  if (padded <= 2 * mag) return 2 * mag;
  if (padded <= 5 * mag) return 5 * mag;
  return 10 * mag;
}

// Returns a "nice" interval so that maxY / interval ≈ steps.
double _niceInterval(double maxY, {int steps = 4}) {
  if (maxY <= 0) return 1;
  final approx = maxY / steps;
  double mag = 1;
  while (mag * 10 <= approx) {
    mag *= 10;
  }
  if (approx <= mag) return mag;
  if (approx <= 2 * mag) return 2 * mag;
  if (approx <= 5 * mag) return 5 * mag;
  return 10 * mag;
}

// How many data-points to skip between X labels, targeting ~5 labels total.
int _xStep(int count) {
  if (count <= 5) return 1;
  if (count <= 10) return 2;
  if (count <= 15) return 3;
  return ((count - 1) / 4).ceil();
}

// X-axis label: HH:MM when same-day; MM-DD HH:00 when multi-day.
String _fmtAxisTime(int tsMs, bool sameDay) {
  final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
  if (sameDay) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

const _axisStyle = TextStyle(fontSize: 9, color: Color(0xFF9CA3AF));

// ── Token chart ───────────────────────────────────────────────────────────────

class _TokenChart extends StatelessWidget {
  final List<_ChartEntry> entries;
  final bool isLine;

  const _TokenChart({required this.entries, required this.isLine});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('暂无数据',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    if (isLine) {
      return LineChart(_buildLineData(entries));
    } else {
      return BarChart(_buildBarData(entries));
    }
  }

  LineChartData _buildLineData(List<_ChartEntry> data) {
    List<FlSpot> inputSpots = [];
    List<FlSpot> outputSpots = [];
    List<FlSpot> totalSpots = [];

    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      inputSpots.add(FlSpot(i.toDouble(), e.inputTokens.toDouble()));
      outputSpots.add(FlSpot(i.toDouble(), e.outputTokens.toDouble()));
      totalSpots.add(FlSpot(
          i.toDouble(), (e.inputTokens + e.outputTokens).toDouble()));
    }

    double rawMax = 0;
    for (final e in data) {
      final t = (e.inputTokens + e.outputTokens).toDouble();
      if (t > rawMax) rawMax = t;
    }
    final maxY = _calcMaxY(rawMax);
    final interval = _niceInterval(maxY);

    final sameDay = data.first.dt.day == data.last.dt.day &&
        data.first.dt.month == data.last.dt.month;
    final step = _xStep(data.length);

    const seriesNames = ['输入', '输出', '合计'];
    const seriesColors = [
      Color(0xFF6366F1),
      Color(0xFF10B981),
      Color(0xFFF59E0B)
    ];

    return LineChartData(
      minY: 0,
      maxY: maxY,
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        getTouchedSpotIndicator: (barData, spotIndexes) =>
            spotIndexes.map((_) {
          return TouchedSpotIndicatorData(
            FlLine(
                color:
                    barData.color?.withAlpha(60) ?? Colors.grey,
                strokeWidth: 1),
            FlDotData(
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: Colors.white,
                strokeColor: bar.color ?? Colors.grey,
                strokeWidth: 2,
              ),
            ),
          );
        }).toList(),
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          tooltipRoundedRadius: 8,
          tooltipBorder:
              const BorderSide(color: Color(0xFFE5E7EB)),
          tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          getTooltipItems: (spots) =>
              spots.asMap().entries.map((entry) {
            final isFirst = entry.key == 0;
            final s = entry.value;
            final dataIdx = s.x.round();
            final name = seriesNames[s.barIndex];
            final color = seriesColors[s.barIndex];
            final valueText = '$name: ${_fmtK(s.y.toInt())}';
            if (isFirst &&
                dataIdx >= 0 &&
                dataIdx < data.length) {
              return LineTooltipItem(
                '${_fmtTooltipTime(data[dataIdx].tsMs)}\n',
                const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 10,
                    fontWeight: FontWeight.w400),
                children: [
                  TextSpan(
                      text: valueText,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600))
                ],
              );
            }
            return LineTooltipItem(valueText,
                TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600));
          }).toList(),
        ),
      ),
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.black.withAlpha(15), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: interval,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value > maxY) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text(_fmtK(value.toInt()),
                    style: _axisStyle),
              );
            },
          ),
        ),
        rightTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            interval: step.toDouble(),
            getTitlesWidget: (value, meta) {
              final idx = value.round();
              if (idx < 0 ||
                  idx >= data.length ||
                  value != idx.toDouble()) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text(
                    _fmtAxisTime(data[idx].tsMs, sameDay),
                    style: _axisStyle),
              );
            },
          ),
        ),
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
      belowBarData:
          BarAreaData(show: true, color: color.withAlpha(20)),
    );
  }

  BarChartData _buildBarData(List<_ChartEntry> data) {
    double rawMax = 0;
    for (final e in data) {
      final t = (e.inputTokens + e.outputTokens).toDouble();
      if (t > rawMax) rawMax = t;
    }
    final maxY = _calcMaxY(rawMax);
    final interval = _niceInterval(maxY);

    final sameDay = data.first.dt.day == data.last.dt.day &&
        data.first.dt.month == data.last.dt.month;
    final step = _xStep(data.length);

    return BarChartData(
      maxY: maxY,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          tooltipRoundedRadius: 8,
          tooltipBorder:
              const BorderSide(color: Color(0xFFE5E7EB)),
          tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          getTooltipItem:
              (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
            '合计: ${_fmtK(rod.toY.toInt())}',
            const TextStyle(
                color: Color(0xFF6366F1),
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.black.withAlpha(15), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: interval,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value > maxY) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text(_fmtK(value.toInt()),
                    style: _axisStyle),
              );
            },
          ),
        ),
        rightTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            interval: step.toDouble(),
            getTitlesWidget: (value, meta) {
              final idx = value.round();
              if (idx < 0 ||
                  idx >= data.length ||
                  value != idx.toDouble()) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text(
                    _fmtAxisTime(data[idx].tsMs, sameDay),
                    style: _axisStyle),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      barGroups: List.generate(
        data.length,
        (i) => BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (data[i].inputTokens + data[i].outputTokens)
                  .toDouble(),
              color: const Color(0xFF6366F1),
              width: 8,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Latency chart ─────────────────────────────────────────────────────────────

class _LatencyChart extends StatelessWidget {
  final List<_ChartEntry> entries;

  const _LatencyChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final data = entries.where((e) => e.latencyMs > 0).toList();
    if (data.isEmpty) {
      return const Center(
        child: Text('暂无数据',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    double rawMax = 0;
    for (final e in data) {
      if (e.latencyMs > rawMax) rawMax = e.latencyMs.toDouble();
    }
    final maxY = _calcMaxY(rawMax);
    final interval = _niceInterval(maxY);

    final sameDay = data.first.dt.day == data.last.dt.day &&
        data.first.dt.month == data.last.dt.month;
    final step = _xStep(data.length);

    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].latencyMs.toDouble()),
    );

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (barData, spotIndexes) =>
              spotIndexes.map((_) {
            return TouchedSpotIndicatorData(
              FlLine(
                  color: const Color(0xFFF59E0B).withAlpha(60),
                  strokeWidth: 1),
              FlDotData(
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: Colors.white,
                  strokeColor: const Color(0xFFF59E0B),
                  strokeWidth: 2,
                ),
              ),
            );
          }).toList(),
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipRoundedRadius: 8,
            tooltipBorder:
                const BorderSide(color: Color(0xFFE5E7EB)),
            tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            getTooltipItems: (spots) =>
                spots.asMap().entries.map((entry) {
              final isFirst = entry.key == 0;
              final s = entry.value;
              final dataIdx = s.x.round();
              final valueText = '${s.y.toInt()} ms';
              if (isFirst &&
                  dataIdx >= 0 &&
                  dataIdx < data.length) {
                return LineTooltipItem(
                  '${_fmtTooltipTime(data[dataIdx].tsMs)}\n',
                  const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10,
                      fontWeight: FontWeight.w400),
                  children: [
                    TextSpan(
                        text: valueText,
                        style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600))
                  ],
                );
              }
              return LineTooltipItem(
                  valueText,
                  const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600));
            }).toList(),
          ),
        ),
        gridData: FlGridData(
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.black.withAlpha(15), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value > maxY) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text('${value.toInt()}ms',
                      style: _axisStyle),
                );
              },
            ),
          ),
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: step.toDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.round();
                if (idx < 0 ||
                    idx >= data.length ||
                    value != idx.toDouble()) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                      _fmtAxisTime(data[idx].tsMs, sameDay),
                      style: _axisStyle),
                );
              },
            ),
          ),
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
                color: const Color(0xFFF59E0B).withAlpha(25)),
          ),
        ],
      ),
    );
  }
}
