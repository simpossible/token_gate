class UsageStats {
  final int requests;
  final int inputTokens;
  final int outputTokens;
  final int avgLatencyMs;

  const UsageStats({
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
    required this.avgLatencyMs,
  });

  // Server returns UsageResponse: total_input_tokens / total_output_tokens / records_count / avg_latency_ms
  factory UsageStats.fromJson(Map<String, dynamic> json) {
    return UsageStats(
      requests: json['records_count'] as int? ?? 0,
      inputTokens: json['total_input_tokens'] as int? ?? 0,
      outputTokens: json['total_output_tokens'] as int? ?? 0,
      avgLatencyMs: (json['avg_latency_ms'] as num?)?.toInt() ?? 0,
    );
  }

  UsageStats copyWith({int? avgLatencyMs}) => UsageStats(
        requests: requests,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      );

  static const empty = UsageStats(
    requests: 0,
    inputTokens: 0,
    outputTokens: 0,
    avgLatencyMs: 0,
  );
}
