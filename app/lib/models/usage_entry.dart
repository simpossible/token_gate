class UsageEntry {
  final String id;
  final String tokenId;
  final String agentType;
  final int inputTokens;
  final int outputTokens;
  final int latencyMs;
  final String model;
  final int createdAtTs;

  const UsageEntry({
    required this.id,
    required this.tokenId,
    required this.agentType,
    required this.inputTokens,
    required this.outputTokens,
    required this.latencyMs,
    required this.model,
    required this.createdAtTs,
  });

  factory UsageEntry.fromJson(Map<String, dynamic> json) {
    return UsageEntry(
      id: json['id'] as String? ?? '',
      tokenId: json['token_id'] as String? ?? '',
      agentType: json['agent_type'] as String? ?? '',
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      model: json['model'] as String? ?? '',
      createdAtTs: (json['created_at_ts'] as num?)?.toInt() ?? 0,
    );
  }

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtTs);
}
