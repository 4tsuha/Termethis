import '../domain/mcp_server_settings.dart';
import '../infrastructure/mcp_streamable_http_server.dart';

enum McpServerState { stopped, starting, running, stopping, failed }

class McpServerStatus {
  const McpServerStatus(this.state, {this.address, this.port, this.error});
  final McpServerState state;
  final String? address;
  final int? port;
  final String? error;
}

class McpServerController {
  McpServerController(this._settingsStore, this._server);

  final McpServerSettingsStore _settingsStore;
  final McpStreamableHttpServer _server;
  McpServerSettings _settings = const McpServerSettings();
  McpServerStatus _status = const McpServerStatus(McpServerState.stopped);

  McpServerSettings get settings => _settings;
  McpServerStatus get status => _status;

  Future<void> load() async {
    _settings = await _settingsStore.read();
    // 保存済みenabledは利用者の希望値であり、プロセス起動時の自動開始には使わない。
    _status = const McpServerStatus(McpServerState.stopped);
  }

  Future<void> saveSettings(McpServerSettings settings) async {
    if (_server.isRunning) {
      throw StateError('設定変更の前にMCPサーバーを停止してください。');
    }
    await _settingsStore.save(settings);
    _settings = settings;
  }

  Future<void> start() async {
    _status = const McpServerStatus(McpServerState.starting);
    try {
      await _server.start(_settings);
      _status = McpServerStatus(
        McpServerState.running,
        address: _server.boundAddress,
        port: _server.boundPort,
      );
    } on Object catch (error) {
      _status = McpServerStatus(McpServerState.failed, error: '$error');
      rethrow;
    }
  }

  Future<void> stop() async {
    _status = const McpServerStatus(McpServerState.stopping);
    await _server.stop();
    _status = const McpServerStatus(McpServerState.stopped);
  }
}
