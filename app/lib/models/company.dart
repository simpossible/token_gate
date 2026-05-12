class Company {
  final String name;
  final String url;
  final List<String> models;

  const Company({required this.name, required this.url, required this.models});

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      name: json['name'] as String,
      url: json['url'] as String,
      models: (json['models'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}
