class ProxyConfig {
  final String host;
  final String port;
  final bool enabled;

  const ProxyConfig({this.host = '', this.port = '', this.enabled = false});

  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    return ProxyConfig(
      host: json['host'] as String? ?? '',
      port: json['port'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'enabled': enabled,
      };
}
