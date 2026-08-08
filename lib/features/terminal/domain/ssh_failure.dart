enum SshFailureCode {
  dnsLookupFailed,
  connectionRefused,
  connectionTimedOut,
  hostKeyRejected,
  hostKeyMismatch,
  authenticationFailed,
  ptyRejected,
  remoteClosed,
  networkLost,
  unexpected,
}

class SshFailure implements Exception {
  const SshFailure(this.code, [this.cause]);

  final SshFailureCode code;
  final Object? cause;

  @override
  String toString() => 'SshFailure($code)';
}
