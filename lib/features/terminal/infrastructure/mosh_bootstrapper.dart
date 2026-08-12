import '../../../src/rust/api/core.dart' as rust;
import '../../connections/domain/connection_profile.dart';
import '../domain/ssh_gateway.dart';
import 'mosh_connection.dart';

class RustMoshBootstrapper {
  const RustMoshBootstrapper();

  Future<MoshConnection> connect({
    required ConnectionProfile profile,
    required SshAuthentication authentication,
    required List<String> trustedHostKeys,
  }) async {
    final result = await rust.moshBootstrap(
      request: rust.RustMoshBootstrapRequest(
        host: profile.host,
        port: profile.port,
        username: profile.username,
        authKind: authentication is SshPrivateKeyAuthentication
            ? 'private_key'
            : 'password',
        password: authentication is SshPasswordAuthentication
            ? authentication.password
            : '',
        privateKeyPem: authentication is SshPrivateKeyAuthentication
            ? authentication.pem
            : '',
        passphrase: authentication is SshPrivateKeyAuthentication
            ? authentication.passphrase
            : null,
        trustedHostKeys: trustedHostKeys,
      ),
    );
    if (result.exitStatus case final status? when status != 0) {
      throw StateError('mosh-server exited with status $status');
    }
    final bootstrap = MoshBootstrap.parse(
      result.output,
      fallbackHost: profile.host,
    );
    return MoshConnection.connect(bootstrap);
  }
}
