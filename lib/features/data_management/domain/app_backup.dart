import '../../command_palette/domain/command_snippet.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/connection_tab.dart';
import '../../connections/domain/ssh_route_configuration.dart';
import '../../settings/domain/app_font.dart';
import '../../settings/domain/terminal_performance_settings.dart';
import '../../terminal/domain/ssh_gateway.dart';
import '../../wake_on_lan/domain/wake_on_lan.dart';

const appBackupFormatVersion = 1;

class AppBackup {
  const AppBackup({
    required this.version,
    required this.createdAt,
    required this.profiles,
    required this.knownHosts,
    required this.tabs,
    required this.snippets,
    required this.routes,
    required this.appFont,
    required this.terminalSettings,
    this.credentialsToReenter = 0,
  });

  final int version;
  final DateTime createdAt;
  final List<ConnectionProfile> profiles;
  final List<KnownHost> knownHosts;
  final List<ConnectionTab> tabs;
  final List<CommandSnippet> snippets;
  final List<SshRouteConfiguration> routes;
  final AppFont appFont;
  final TerminalPerformanceSettings terminalSettings;
  final int credentialsToReenter;

  Map<String, Object?> toJson() => {
    'format': 'termethis-backup',
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'containsCredentials': false,
    'credentialsToReenter': credentialsToReenter,
    'profiles': profiles.map(_profileToJson).toList(growable: false),
    'knownHosts': knownHosts.map(_knownHostToJson).toList(growable: false),
    'tabs': tabs.map((tab) => tab.toJson()).toList(growable: false),
    'snippets': snippets
        .map((snippet) => snippet.toJson())
        .toList(growable: false),
    'routes': routes.map((route) => route.toJson()).toList(growable: false),
    'settings': {
      'appFont': appFont.name,
      'terminal': _terminalSettingsToJson(terminalSettings),
    },
  };

  factory AppBackup.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'termethis-backup' ||
        json['version'] != appBackupFormatVersion ||
        json['containsCredentials'] != false) {
      throw const FormatException('対応していないバックアップ形式です。');
    }
    final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}');
    if (createdAt == null) {
      throw const FormatException('バックアップの作成日時が不正です。');
    }
    final settings = _map(json['settings']);
    final fontName = settings['appFont'];
    final appFont = AppFont.values
        .where((value) => value.name == fontName)
        .firstOrNull;
    if (appFont == null) {
      throw const FormatException('バックアップのフォント設定が不正です。');
    }
    return AppBackup(
      version: appBackupFormatVersion,
      createdAt: createdAt.toUtc(),
      profiles: _list(
        json['profiles'],
      ).map(_profileFromJson).toList(growable: false),
      knownHosts: _list(
        json['knownHosts'],
      ).map(_knownHostFromJson).toList(growable: false),
      tabs: _list(json['tabs'])
          .map(ConnectionTab.fromJson)
          .whereType<ConnectionTab>()
          .toList(growable: false),
      snippets: _list(json['snippets'])
          .map(CommandSnippet.fromJson)
          .whereType<CommandSnippet>()
          .toList(growable: false),
      routes: _list(json['routes'])
          .map(SshRouteConfiguration.fromJson)
          .whereType<SshRouteConfiguration>()
          .toList(growable: false),
      appFont: appFont,
      terminalSettings: _terminalSettingsFromJson(_map(settings['terminal'])),
      credentialsToReenter: switch (json['credentialsToReenter']) {
        final int value when value >= 0 => value,
        _ => 0,
      },
    );
  }
}

class AppBackupPreview {
  const AppBackupPreview({
    required this.backup,
    required this.newProfiles,
    required this.updatedProfiles,
    required this.credentialsToReenter,
    required this.skippedTabs,
  });

  final AppBackup backup;
  final int newProfiles;
  final int updatedProfiles;
  final int credentialsToReenter;
  final int skippedTabs;
}

Map<String, Object?> _profileToJson(ConnectionProfile profile) => {
  'id': profile.id,
  'name': profile.name,
  'host': profile.host,
  'port': profile.port,
  'username': profile.username,
  'connectionType': profile.connectionType.name,
  'authenticationType': profile.authenticationType.name,
  'requiresCredentialReentry': profile.credentialReference != null,
  'remotePath': profile.remotePath,
  if (profile.wakeOnLan case final wake?)
    'wakeOnLan': {
      'macAddress': wake.macAddress,
      'broadcastAddress': wake.broadcastAddress,
      'port': wake.port,
    },
};

ConnectionProfile _profileFromJson(Object? value) {
  final json = _map(value);
  final id = _requiredString(json, 'id');
  final name = _requiredString(json, 'name');
  final host = _requiredString(json, 'host');
  final port = json['port'];
  final username = json['username'];
  final connectionType = ConnectionType.values
      .where((item) => item.name == json['connectionType'])
      .firstOrNull;
  final authenticationType = AuthenticationType.values
      .where((item) => item.name == json['authenticationType'])
      .firstOrNull;
  if (port is! int ||
      port < 1 ||
      port > 65535 ||
      username is! String ||
      connectionType == null ||
      authenticationType == null) {
    throw const FormatException('接続先の項目が不正です。');
  }
  final wakeJson = json['wakeOnLan'];
  WakeOnLanConfiguration? wakeOnLan;
  if (wakeJson != null) {
    final wake = _map(wakeJson);
    final mac = _requiredString(wake, 'macAddress');
    final broadcast = _requiredString(wake, 'broadcastAddress');
    final wakePort = wake['port'];
    if (WakeOnLanConfiguration.normalizeMacAddress(mac) == null ||
        !WakeOnLanConfiguration.isValidIpv4Address(broadcast) ||
        wakePort is! int ||
        wakePort < 1 ||
        wakePort > 65535) {
      throw const FormatException('Wake on LAN設定が不正です。');
    }
    wakeOnLan = WakeOnLanConfiguration(
      macAddress: mac,
      broadcastAddress: broadcast,
      port: wakePort,
    );
  }
  return ConnectionProfile(
    id: id,
    name: name,
    host: host,
    port: port,
    username: username,
    connectionType: connectionType,
    authenticationType: authenticationType,
    credentialReference: null,
    privateKeyLabel: null,
    wakeOnLan: wakeOnLan,
    remotePath: json['remotePath'] is String
        ? json['remotePath'] as String
        : null,
  );
}

Map<String, Object?> _knownHostToJson(KnownHost host) => {
  'host': host.info.host,
  'port': host.info.port,
  'algorithm': host.info.algorithm,
  'fingerprintSha256': host.info.fingerprintSha256,
  'acceptedAt': host.acceptedAt.toUtc().toIso8601String(),
};

KnownHost _knownHostFromJson(Object? value) {
  final json = _map(value);
  final acceptedAt = DateTime.tryParse('${json['acceptedAt'] ?? ''}');
  final port = json['port'];
  if (acceptedAt == null || port is! int || port < 1 || port > 65535) {
    throw const FormatException('known_hostsの項目が不正です。');
  }
  return KnownHost(
    info: HostKeyInfo(
      host: _requiredString(json, 'host'),
      port: port,
      algorithm: _requiredString(json, 'algorithm'),
      fingerprintSha256: _requiredString(json, 'fingerprintSha256'),
    ),
    acceptedAt: acceptedAt.toUtc(),
  );
}

Map<String, Object?> _terminalSettingsToJson(
  TerminalPerformanceSettings value,
) => {
  'rendererMode': value.rendererMode.name,
  'terminalFont': value.terminalFont.name,
  'hardwareAccelerationMode': value.hardwareAccelerationMode.name,
  'refreshRateMode': value.refreshRateMode.name,
  'scrollbackLines': value.scrollbackLines,
  'keepAliveInBackground': value.keepAliveInBackground,
  'showSearchButton': value.showSearchButton,
  'showCopyOutputButton': value.showCopyOutputButton,
  'searchMode': value.searchMode.name,
  'keepScreenAwake': value.keepScreenAwake,
  'mouseInput': value.mouseInput,
  'longPressRightClick': value.longPressRightClick,
  'tapToMovePromptCursor': value.tapToMovePromptCursor,
  'showSessionTabBar': value.showSessionTabBar,
  'resizeForKeyboard': value.resizeForKeyboard,
};

TerminalPerformanceSettings _terminalSettingsFromJson(
  Map<String, dynamic> json,
) {
  T enumValue<T extends Enum>(List<T> values, String key, T fallback) =>
      values.where((value) => value.name == json[key]).firstOrNull ?? fallback;
  final lines = json['scrollbackLines'];
  return TerminalPerformanceSettings(
    rendererMode: enumValue(
      TerminalRendererMode.values,
      'rendererMode',
      TerminalRendererMode.connectBot,
    ),
    terminalFont: enumValue(
      TerminalFont.values,
      'terminalFont',
      TerminalFont.cascadiaMono,
    ),
    hardwareAccelerationMode: enumValue(
      HardwareAccelerationMode.values,
      'hardwareAccelerationMode',
      HardwareAccelerationMode.automatic,
    ),
    refreshRateMode: enumValue(
      RefreshRateMode.values,
      'refreshRateMode',
      RefreshRateMode.adaptive,
    ),
    scrollbackLines:
        lines is int &&
            TerminalPerformanceSettings.supportedScrollbackLines.contains(lines)
        ? lines
        : 2000,
    keepAliveInBackground: json['keepAliveInBackground'] == true,
    showSearchButton: json['showSearchButton'] != false,
    showCopyOutputButton: json['showCopyOutputButton'] != false,
    searchMode: enumValue(
      TerminalSearchMode.values,
      'searchMode',
      TerminalSearchMode.shell,
    ),
    keepScreenAwake: json['keepScreenAwake'] == true,
    mouseInput: json['mouseInput'] == true,
    longPressRightClick: json['longPressRightClick'] == true,
    tapToMovePromptCursor: json['tapToMovePromptCursor'] == true,
    showSessionTabBar: json['showSessionTabBar'] != false,
    resizeForKeyboard: json['resizeForKeyboard'] == true,
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('バックアップの構造が不正です。');
  return value.map((key, value) => MapEntry('$key', value));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('バックアップの一覧が不正です。');
  return value;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$keyが不正です。');
  }
  return value;
}
