class UsageEntry {
  final int id;
  final int configId;
  final int inputTokens;
  final int outputTokens;
  final int createdAtTs;

  const UsageEntry({
    required this.id,
    required this.configId,
    required this.inputTokens,
    required this.outputTokens,
    required this.createdAtTs,
  });

  factory UsageEntry.fromJson(Map<String, dynamic> json) {
    return UsageEntry(
      id: json['id'] as int? ?? 0,
      configId: json['config_id'] as int? ?? 0,
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      createdAtTs: json['created_at_ts'] as int? ?? 0,
    );
  }

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtTs);
}

class UsageDelta {
  final int inputTokens;
  final int outputTokens;

  const UsageDelta({required this.inputTokens, required this.outputTokens});

  factory UsageDelta.fromJson(Map<String, dynamic> json) {
    return UsageDelta(
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
    );
  }
}
