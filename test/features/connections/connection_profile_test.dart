import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';

void main() {
  test('接続方式ごとの既定ポートを使用する', () {
    expect(ConnectionType.ssh.defaultPort, 22);
    expect(ConnectionType.rdp.defaultPort, 3389);
    expect(ConnectionType.vnc.defaultPort, 5900);
  });

  test('リモートデスクトップの接続先表示を組み立てる', () {
    const rdp = ConnectionProfile(
      id: 'rdp',
      name: 'Windows',
      host: 'rdp.example.com',
      port: 3389,
      username: 'operator',
      connectionType: ConnectionType.rdp,
    );
    const vnc = ConnectionProfile(
      id: 'vnc',
      name: 'VNC',
      host: 'vnc.example.com',
      port: 5900,
      username: '',
      connectionType: ConnectionType.vnc,
    );

    expect(rdp.target, 'operator · rdp.example.com:3389');
    expect(vnc.target, 'vnc.example.com:5900');
  });
}
