import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/terminal/domain/ssh_gateway.dart';
import 'package:ssh_terminal_ja/infrastructure/ssh/in_memory_host_key_repository.dart';

void main() {
  test('ホスト名の大文字小文字を区別せずポートごとに鍵を保持する', () async {
    final repository = InMemoryHostKeyRepository();
    final knownHost = KnownHost(
      info: const HostKeyInfo(
        host: 'Example.COM',
        port: 22,
        algorithm: 'ssh-ed25519',
        fingerprintSha256: 'SHA256:test',
      ),
      acceptedAt: DateTime(2026, 8, 8),
    );

    await repository.trust(knownHost);

    expect(await repository.find('example.com.', 22), [same(knownHost)]);
    expect(await repository.find('example.com', 2222), isEmpty);
  });
}
