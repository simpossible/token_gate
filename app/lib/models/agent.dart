class Agent {
  final String type;
  final String label;
  final String? activeConfigId;
  final String? activeConfigName;

  const Agent({
    required this.type,
    required this.label,
    this.activeConfigId,
    this.activeConfigName,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      type: json['type'] as String,
      label: json['label'] as String,
      activeConfigId: json['active_config_id'] as String?,
      activeConfigName: json['active_config_name'] as String?,
    );
  }
}
