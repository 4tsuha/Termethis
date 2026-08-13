enum VaultProtectionMode {
  none,
  everyUnlock,
  thirtySeconds,
  fiveMinutes;

  Duration? get validity => switch (this) {
    none => null,
    everyUnlock => Duration.zero,
    thirtySeconds => const Duration(seconds: 30),
    fiveMinutes => const Duration(minutes: 5),
  };
}

enum VaultAuthenticationResult {
  unlocked,
  unavailable,
  canceled,
  keyInvalidated,
  backgroundDenied,
}

class VaultProtectionStatus {
  const VaultProtectionStatus({
    required this.available,
    required this.deviceCredentialAvailable,
    required this.strongBiometricAvailable,
    required this.locked,
    this.keyInvalidated = false,
  });

  final bool available;
  final bool deviceCredentialAvailable;
  final bool strongBiometricAvailable;
  final bool locked;
  final bool keyInvalidated;
}

abstract interface class VaultProtectionGateway {
  Future<VaultProtectionStatus> status(VaultProtectionMode mode);
  Future<VaultAuthenticationResult> unlock(VaultProtectionMode mode);
  Future<void> configure(VaultProtectionMode mode);
  Future<void> lock();
}

class UnavailableVaultProtectionGateway implements VaultProtectionGateway {
  const UnavailableVaultProtectionGateway();

  @override
  Future<void> configure(VaultProtectionMode mode) async {}

  @override
  Future<void> lock() async {}

  @override
  Future<VaultProtectionStatus> status(VaultProtectionMode mode) async =>
      VaultProtectionStatus(
        available: mode == VaultProtectionMode.none,
        deviceCredentialAvailable: false,
        strongBiometricAvailable: false,
        locked: mode != VaultProtectionMode.none,
      );

  @override
  Future<VaultAuthenticationResult> unlock(VaultProtectionMode mode) async =>
      mode == VaultProtectionMode.none
      ? VaultAuthenticationResult.unlocked
      : VaultAuthenticationResult.unavailable;
}
