class Agent {
  final String type;
  final String label;

  const Agent({required this.type, required this.label});

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      type: json['type'] as String,
      label: json['label'] as String,
    );
  }
}
