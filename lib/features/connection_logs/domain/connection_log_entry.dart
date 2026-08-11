import '../../terminal/domain/ssh_failure.dart';

enum ConnectionLogState {
  idle,
  connecting,
  verifyingHost,
  authenticating,
  openingPty,
  connected,
  reconnectPrompt,
  closing,
  closed,
  failed,
}

class ConnectionLogEntry {
  const ConnectionLogEntry({
    required this.timestamp,
    required this.profileId,
    required this.profileName,
    required this.target,
    required this.tabId,
    required this.state,
    this.failureCode,
  });

  final DateTime timestamp;
  final String profileId;
  final String profileName;
  final String target;
  final String tabId;
  final ConnectionLogState state;
  final SshFailureCode? failureCode;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'profileId': profileId,
    'profileName': profileName,
    'target': target,
    'tabId': tabId,
    'state': state.name,
    'failureCode': failureCode?.name,
  };

  static ConnectionLogEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final timestamp = DateTime.tryParse(value['timestamp'] as String? ?? '');
    final profileId = value['profileId'];
    final profileName = value['profileName'];
    final target = value['target'];
    final tabId = value['tabId'];
    final stateName = value['state'];
    if (timestamp == null ||
        profileId is! String ||
        profileName is! String ||
        target is! String ||
        tabId is! String ||
        stateName is! String) {
      return null;
    }
    final state = ConnectionLogState.values.where(
      (candidate) => candidate.name == stateName,
    );
    if (state.isEmpty) return null;
    final failureName = value['failureCode'];
    final failures = SshFailureCode.values.where(
      (candidate) => candidate.name == failureName,
    );
    return ConnectionLogEntry(
      timestamp: timestamp.toLocal(),
      profileId: profileId,
      profileName: profileName,
      target: target,
      tabId: tabId,
      state: state.first,
      failureCode: failures.isEmpty ? null : failures.first,
    );
  }
}
