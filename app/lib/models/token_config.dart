class TokenConfig {
  final int id;
  final String name;
  final String apiKey;
  final String url;
  final String model;
  final String agentType;
  final bool isActive;
  final String createdAt;

  const TokenConfig({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.url,
    required this.model,
    required this.agentType,
    required this.isActive,
    required this.createdAt,
  });

  factory TokenConfig.fromJson(Map<String, dynamic> json) {
    return TokenConfig(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      url: json['url'] as String? ?? '',
      model: json['model'] as String? ?? '',
      agentType: json['agent_type'] as String? ?? '',
      isActive: (json['is_active'] as int? ?? 0) == 1,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'api_key': apiKey,
        'url': url,
        'model': model,
        'agent_type': agentType,
      };

  TokenConfig copyWith({
    int? id,
    String? name,
    String? apiKey,
    String? url,
    String? model,
    String? agentType,
    bool? isActive,
    String? createdAt,
  }) {
    return TokenConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey,
      url: url ?? this.url,
      model: model ?? this.model,
      agentType: agentType ?? this.agentType,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
