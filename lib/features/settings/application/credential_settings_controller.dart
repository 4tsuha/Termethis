import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/credential_vault.dart';
import '../domain/credential_settings.dart';

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

  Future<void> _removeSavedPasswords() async {
    final repository = ref.read(connectionProfileRepositoryProvider);
    final vault = ref.read(credentialVaultProvider);
    final profiles = await repository.watchAll().first;
    for (final profile in profiles) {
      final reference = profile.credentialReference;
      if (profile.authenticationType !=
              AuthenticationType.passwordOrInteractive ||
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
