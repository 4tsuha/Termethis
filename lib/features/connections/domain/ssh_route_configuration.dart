class SshRouteConfiguration {
  const SshRouteConfiguration({
    required this.profileId,
    this.jumpProfileIds = const [],
  });

  final String profileId;
  final List<String> jumpProfileIds;

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'jumpProfileIds': jumpProfileIds,
  };

  static SshRouteConfiguration? fromJson(Object? value) {
    if (value is! Map || value['profileId'] is! String) return null;
    return SshRouteConfiguration(
      profileId: value['profileId'] as String,
      jumpProfileIds:
          (value['jumpProfileIds'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }
}

abstract interface class SshRouteStore {
  Future<List<SshRouteConfiguration>> load();
  Future<void> save(List<SshRouteConfiguration> routes);
}

class EphemeralSshRouteStore implements SshRouteStore {
  List<SshRouteConfiguration> _routes = const [];

  @override
  Future<List<SshRouteConfiguration>> load() async =>
      List.unmodifiable(_routes);

  @override
  Future<void> save(List<SshRouteConfiguration> routes) async {
    _routes = List.unmodifiable(routes);
  }
}

class SshRouteCycleException implements Exception {
  const SshRouteCycleException(this.profileIds);
  final List<String> profileIds;
}
