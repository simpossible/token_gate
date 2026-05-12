class LatestLatencyResponse {
  final String tokenId;
  final int latestLatencyMs;
  final bool hasData;

  const LatestLatencyResponse({
    required this.tokenId,
    required this.latestLatencyMs,
    required this.hasData,
  });

  factory LatestLatencyResponse.fromJson(Map<String, dynamic> json) {
    return LatestLatencyResponse(
      tokenId: json['token_id'] as String? ?? '',
      latestLatencyMs: (json['latest_latency_ms'] as num?)?.toInt() ?? 0,
      hasData: json['has_data'] as bool? ?? false,
    );
  }
}
