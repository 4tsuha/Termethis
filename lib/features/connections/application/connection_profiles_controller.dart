import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/connection_profile.dart';
import '../domain/connection_profile_repository.dart';
import '../domain/credential_vault.dart';

final connectionProfileRepositoryProvider =
    Provider<ConnectionProfileRepository>((ref) {
      final repository = EphemeralConnectionProfileRepository();
      ref.onDispose(repository.close);
      return repository;
    });

final connectionProfilesProvider =
    StreamNotifierProvider<
      ConnectionProfilesController,
      List<ConnectionProfile>
    >(ConnectionProfilesController.new);

final credentialVaultProvider = Provider<CredentialVault>(
  (ref) => EphemeralCredentialVault(),
);

class ConnectionProfilesController
    extends StreamNotifier<List<ConnectionProfile>> {
  late ConnectionProfileRepository _repository;
  late CredentialVault _vault;

  @override
  Stream<List<ConnectionProfile>> build() {
    _repository = ref.watch(connectionProfileRepositoryProvider);
    _vault = ref.watch(credentialVaultProvider);
    return _repository.watchAll();
  }

  ConnectionProfile? findById(String id) {
    final profiles = state.value;
    if (profiles == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  Future<ConnectionProfile?> loadById(String id) => _repository.findById(id);

  Future<ConnectionProfile> save(
    ConnectionProfile profile, {
    PrivateKeyCredential? replacementPrivateKey,
  }) async {
    final existing = await _repository.findById(profile.id);
    CredentialHandle? newHandle;
    var savedProfile = profile;

    if (replacementPrivateKey != null) {
      newHandle = await _vault.putPrivateKey(replacementPrivateKey);
      savedProfile = profile.withCredential(
        credentialReference: newHandle.value,
        privateKeyLabel: replacementPrivateKey.label,
      );
    }

    try {
      await _repository.save(savedProfile);
    } catch (_) {
      if (newHandle != null) {
        await _vault.delete(newHandle);
      }
      rethrow;
    }

    final previousReference = existing?.credentialReference;
    if (previousReference != null &&
        previousReference != savedProfile.credentialReference) {
      await _vault.delete(CredentialHandle(previousReference));
    }
    return savedProfile;
  }

  Future<void> delete(String id) async {
    final profile = await _repository.findById(id);
    await _repository.delete(id);
    final reference = profile?.credentialReference;
    if (reference != null) {
      await _vault.delete(CredentialHandle(reference));
    }
  }
}
