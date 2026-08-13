import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/terminal/domain/ssh_failure.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/infrastructure/ssh/in_memory_host_key_repository.dart';
import 'package:termethis/infrastructure/ssh/rust_ssh_gateway.dart';
import 'package:termethis/src/rust/api/core.dart' as rust;

void main() {
  const profile = ConnectionProfile(
    id: 'host-key-flow',
    name: 'テスト接続先',
    host: 'ssh.example.com',
    port: 22,
    username: 'tester',
  );

  test('未知のホスト鍵承認後は同じ接続上で公開鍵認証を続行する', () async {
    final calls = <String>[];
    final gateway = RustSshGateway(
      InMemoryHostKeyRepository(),
      connect: ({required request}) async {
        calls.add('connect');
        return const rust.RustSshConnectResult(
          pendingHostKeyId: 41,
          hostKey: rust.RustHostKey(
            algorithm: 'ssh-ed25519',
            fingerprintSha256: 'SHA256:test',
          ),
          errorCode: 'host_key_confirmation_required',
        );
      },
      continueHostKey: ({required pendingHostKeyId, required approved}) async {
        calls.add('continue:$pendingHostKeyId:$approved');
        return const rust.RustSshConnectResult(sessionId: 7);
      },
      connectionFactory: (_) => _FakeConnection(),
    );

    var authenticationStarted = false;
    final connection = await gateway.connect(
      SshConnectRequest(
        profile: profile,
        authentication: const SshPrivateKeyAuthentication(pem: 'key'),
        onUnknownHostKey: (_) async {
          calls.add('approve');
          return true;
        },
        onInteractivePrompt: (_) async => const [],
        onAuthenticationStarted: () {
          authenticationStarted = true;
          calls.add('authentication');
        },
        onOpeningPty: () => calls.add('pty'),
        terminalWidth: 80,
        terminalHeight: 24,
      ),
    );

    expect(calls, [
      'connect',
      'approve',
      'authentication',
      'continue:41:true',
      'pty',
    ]);
    expect(authenticationStarted, isTrue);
    await connection.close();
  });

  test('未知のホスト鍵を拒否すると保留接続へ拒否を返す', () async {
    final calls = <String>[];
    final gateway = RustSshGateway(
      InMemoryHostKeyRepository(),
      connect: ({required request}) async => const rust.RustSshConnectResult(
        pendingHostKeyId: 42,
        hostKey: rust.RustHostKey(
          algorithm: 'ssh-ed25519',
          fingerprintSha256: 'SHA256:rejected',
        ),
        errorCode: 'host_key_confirmation_required',
      ),
      continueHostKey: ({required pendingHostKeyId, required approved}) async {
        calls.add('continue:$pendingHostKeyId:$approved');
        return const rust.RustSshConnectResult(errorCode: 'host_key_rejected');
      },
    );

    await expectLater(
      gateway.connect(
        SshConnectRequest(
          profile: profile,
          authentication: const SshPrivateKeyAuthentication(pem: 'key'),
          onUnknownHostKey: (_) async => false,
          onInteractivePrompt: (_) async => const [],
          onAuthenticationStarted: () {},
          onOpeningPty: () {},
          terminalWidth: 80,
          terminalHeight: 24,
        ),
      ),
      throwsA(
        isA<SshFailure>().having(
          (failure) => failure.code,
          'code',
          SshFailureCode.hostKeyRejected,
        ),
      ),
    );
    expect(calls, ['continue:42:false']);
  });
}

class _FakeConnection implements SshConnection {
  @override
  Stream<Uint8List> get stdout => const Stream.empty();

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  Future<void> get done => Future<void>.value();

  @override
  void write(Uint8List data) {}

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Future<void> close() async {}
}
