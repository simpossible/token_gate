class LatencyEntry {
  final int ttfbMs;
  final int createdAtTs;

  const LatencyEntry({required this.ttfbMs, required this.createdAtTs});

  factory LatencyEntry.fromJson(Map<String, dynamic> json) {
    return LatencyEntry(
      ttfbMs: json['ttfb_ms'] as int? ?? 0,
      createdAtTs: json['created_at_ts'] as int? ?? 0,
    );
  }

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtTs);
}
