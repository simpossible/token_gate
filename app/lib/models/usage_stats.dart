class UsageStats {
  final int requests;
  final int inputTokens;
  final int outputTokens;
  final double avgLatencyMs;

  const UsageStats({
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
    required this.avgLatencyMs,
  });

  factory UsageStats.fromJson(Map<String, dynamic> json) {
    return UsageStats(
      requests: json['requests'] as int? ?? 0,
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      avgLatencyMs: (json['avg_latency_ms'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static const empty = UsageStats(
    requests: 0,
    inputTokens: 0,
    outputTokens: 0,
    avgLatencyMs: 0.0,
  );
}
