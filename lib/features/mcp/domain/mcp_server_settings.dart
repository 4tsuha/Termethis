class McpServerSettings {
  const McpServerSettings({
    this.enabled = false,
    this.allowLan = false,
    this.port = 8765,
    this.bearerToken = '',
  });

  final bool enabled;
  final bool allowLan;
  final int port;
  final String bearerToken;

  String get bindAddress => allowLan ? '0.0.0.0' : '127.0.0.1';

  McpServerSettings copyWith({
    bool? enabled,
    bool? allowLan,
    int? port,
    String? bearerToken,
  }) => McpServerSettings(
    enabled: enabled ?? this.enabled,
    allowLan: allowLan ?? this.allowLan,
    port: port ?? this.port,
    bearerToken: bearerToken ?? this.bearerToken,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'allowLan': allowLan,
    'port': port,
    'bearerToken': bearerToken,
  };

  factory McpServerSettings.fromJson(Map<String, Object?> json) {
    final port = json['port'] as int? ?? 8765;
    return McpServerSettings(
      enabled: json['enabled'] as bool? ?? false,
      allowLan: json['allowLan'] as bool? ?? false,
      port: port >= 1 && port <= 65535 ? port : 8765,
      bearerToken: json['bearerToken'] as String? ?? '',
    );
  }
}

abstract interface class McpServerSettingsStore {
  Future<McpServerSettings> read();
  Future<void> save(McpServerSettings settings);
}
