import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/credential_vault.dart';
import '../domain/credential_settings.dart';
import '../domain/vault_protection.dart';

final vaultProtectionGatewayProvider = Provider<VaultProtectionGateway>(
  (ref) => const UnavailableVaultProtectionGateway(),
);

final vaultProtectionStatusProvider = FutureProvider<VaultProtectionStatus>(
  (ref) => ref
      .watch(vaultProtectionGatewayProvider)
      .status(ref.watch(credentialSettingsProvider).vaultProtectionMode),
);

final initialCredentialSettingsProvider = Provider<CredentialSettings>(
  (ref) => const CredentialSettings(),
);

final credentialSettingsStoreProvider = Provider<CredentialSettingsStore>(
  (ref) => const EphemeralCredentialSettingsStore(),
);

final credentialSettingsProvider =
    NotifierProvider<CredentialSettingsController, CredentialSettings>(
      CredentialSettingsController.new,
    );

class CredentialSettingsController extends Notifier<CredentialSettings> {
  late CredentialSettingsStore _store;

  @override
  CredentialSettings build() {
    _store = ref.watch(credentialSettingsStoreProvider);
    return ref.watch(initialCredentialSettingsProvider);
  }

  Future<void> setSaveSshPasswords(bool enabled) async {
    if (state.saveSshPasswords == enabled) return;
    state = state.copyWith(saveSshPasswords: enabled);
    await _store.save(state);
    if (!enabled) await _removeSavedPasswords();
  }

  Future<VaultAuthenticationResult> setVaultProtectionMode(
    VaultProtectionMode mode,
  ) async {
    final gateway = ref.read(vaultProtectionGatewayProvider);
    if (mode != VaultProtectionMode.none) {
      final result = await gateway.unlock(mode);
      if (result != VaultAuthenticationResult.unlocked) return result;
    }
    await gateway.configure(mode);
    final vault = ref.read(credentialVaultProvider);
    if (vault case final LockableCredentialVault lockable) {
      lockable.setProtectionMode(mode);
    }
    state = state.copyWith(vaultProtectionMode: mode);
    await _store.save(state);
    ref.invalidate(vaultProtectionStatusProvider);
    return VaultAuthenticationResult.unlocked;
  }

  Future<void> lockVault() async {
    await ref.read(vaultProtectionGatewayProvider).lock();
    final vault = ref.read(credentialVaultProvider);
    if (vault case final LockableCredentialVault lockable) {
      lockable.clearCachedSecrets();
    }
    ref.invalidate(vaultProtectionStatusProvider);
  }

  Future<VaultAuthenticationResult> unlockVault() async {
    final mode = state.vaultProtectionMode;
    final result = await ref.read(vaultProtectionGatewayProvider).unlock(mode);
    ref.invalidate(vaultProtectionStatusProvider);
    return result;
  }

  Future<void> _removeSavedPasswords() async {
    final repository = ref.read(connectionProfileRepositoryProvider);
    final vault = ref.read(credentialVaultProvider);
    final profiles = await repository.watchAll().first;
    for (final profile in profiles) {
      final reference = profile.credentialReference;
      if ((profile.authenticationType !=
                  AuthenticationType.passwordOrInteractive &&
              profile.connectionType != ConnectionType.opencode) ||
          reference == null) {
        continue;
      }
      await repository.save(
        profile.withCredential(
          credentialReference: null,
          privateKeyLabel: null,
        ),
      );
      await vault.delete(CredentialHandle(reference));
    }
  }
}
