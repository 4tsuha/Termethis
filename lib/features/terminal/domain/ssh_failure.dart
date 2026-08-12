enum SshFailureCode {
  dnsLookupFailed,
  connectionRefused,
  connectionTimedOut,
  hostKeyRejected,
  hostKeyMismatch,
  authenticationFailed,
  privateKeyInvalid,
  keyPassphraseRequired,
  ptyRejected,
  remoteClosed,
  networkLost,
  unexpected,
  vaultLocked,
  biometricUnavailable,
  biometricCanceled,
  keystoreKeyInvalidated,
  jumpHostConnectionFailed,
  jumpHostAuthenticationFailed,
  jumpHostKeyRejected,
  tunnelBindFailed,
  tunnelRemoteRejected,
  socksProtocolError,
  moshServerMissing,
  moshUdpUnreachable,
  moshProtocolMismatch,
  simdUnavailable,
  keyDecodeFailed,
  sessionProfileMissing,
  remoteDesktopDisconnected,
}

class SshFailure implements Exception {
  const SshFailure(this.code, [this.cause]);

  final SshFailureCode code;
  final Object? cause;

  @override
  String toString() => 'SshFailure($code)';
}
