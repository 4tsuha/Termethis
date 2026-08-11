class SshTab {
  const SshTab({
    required this.id,
    required this.profileId,
    required this.title,
    this.restored = false,
  });

  final String id;
  final String profileId;
  final String title;
  final bool restored;

  SshTab copyWith({String? title, bool? restored}) => SshTab(
    id: id,
    profileId: profileId,
    title: title ?? this.title,
    restored: restored ?? this.restored,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'title': title,
  };

  static SshTab? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final profileId = value['profileId'];
    final title = value['title'];
    if (id is! String || profileId is! String || title is! String) return null;
    return SshTab(id: id, profileId: profileId, title: title, restored: true);
  }
}

abstract interface class SshTabStore {
  Future<List<SshTab>> load();
  Future<void> save(List<SshTab> tabs);
}

class EphemeralSshTabStore implements SshTabStore {
  List<SshTab> _tabs = const [];

  @override
  Future<List<SshTab>> load() async => [
    for (final tab in _tabs) tab.copyWith(restored: true),
  ];

  @override
  Future<void> save(List<SshTab> tabs) async {
    _tabs = List.unmodifiable(tabs);
  }
}
