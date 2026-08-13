import 'package:flutter/services.dart';

import '../../features/settings/domain/vault_protection.dart';

class AndroidVaultProtectionGateway implements VaultProtectionGateway {
  const AndroidVaultProtectionGateway();

  static const _channel = MethodChannel('jp.yts.termethis/vault_protection');

  @override
  Future<void> configure(VaultProtectionMode mode) =>
      _channel.invokeMethod<void>('configure', {'mode': mode.name});

  @override
  Future<void> lock() => _channel.invokeMethod<void>('lock');

  @override
  Future<VaultProtectionStatus> status(VaultProtectionMode mode) async {
    final value = await _channel.invokeMapMethod<String, Object?>('status', {
      'mode': mode.name,
    });
    return VaultProtectionStatus(
      available: value?['available'] == true,
      deviceCredentialAvailable: value?['deviceCredentialAvailable'] == true,
      strongBiometricAvailable: value?['strongBiometricAvailable'] == true,
      locked: value?['locked'] != false,
      keyInvalidated: value?['keyInvalidated'] == true,
    );
  }

  @override
  Future<VaultAuthenticationResult> unlock(VaultProtectionMode mode) async {
    final result = await _channel.invokeMethod<String>('unlock', {
      'mode': mode.name,
    });
    return VaultAuthenticationResult.values.firstWhere(
      (value) => value.name == result,
      orElse: () => VaultAuthenticationResult.unavailable,
    );
  }
}
