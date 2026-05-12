class UsageStats {
  final int requests;
  final int inputTokens;
  final int outputTokens;

  const UsageStats({
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
  });

  // Server returns UsageResponse: total_input_tokens / total_output_tokens / records_count
  factory UsageStats.fromJson(Map<String, dynamic> json) {
    return UsageStats(
      requests: json['records_count'] as int? ?? 0,
      inputTokens: json['total_input_tokens'] as int? ?? 0,
      outputTokens: json['total_output_tokens'] as int? ?? 0,
    );
  }

  static const empty = UsageStats(
    requests: 0,
    inputTokens: 0,
    outputTokens: 0,
  );
}
