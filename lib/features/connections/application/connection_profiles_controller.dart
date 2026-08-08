import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/connection_profile.dart';

final connectionProfilesProvider =
    NotifierProvider<ConnectionProfilesController, List<ConnectionProfile>>(
      ConnectionProfilesController.new,
    );

class ConnectionProfilesController extends Notifier<List<ConnectionProfile>> {
  @override
  List<ConnectionProfile> build() {
    return const [];
  }

  ConnectionProfile? findById(String id) {
    for (final profile in state) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  void save(ConnectionProfile profile) {
    final index = state.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      state = [...state, profile];
      return;
    }

    final next = [...state];
    next[index] = profile;
    state = next;
  }

  void delete(String id) {
    state = state.where((profile) => profile.id != id).toList(growable: false);
  }
}
